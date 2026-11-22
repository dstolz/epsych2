function R = bench_rig_report(S, options)
% R = bench_rig_report(S)
% R = bench_rig_report(file)
% R = bench_rig_report(S, Warmup=5, BlockSize=50, Quiet=true)
% Read what tmp/bench_rig_preview.m recorded: what a trial boundary cost the
% subject and the MATLAB thread, whether that grew over the session, and which
% functions it was spent in.
%
% Three numbers describe a boundary:
%   waited  - trial found complete to the end of the NewTrial pulse. The
%             subject waits through this.
%   tick    - the whole timer tick the boundary ran in, including the display
%             work deferred until after the pulse.
%   hold    - how much later than usual the NEXT tick started: the queued
%             graphics being flushed after the callback returned. Nothing in
%             the trial loop can time this from inside.
% waited + (tick - waited) + hold is how long the MATLAB thread was taken.
%
% Boundaries come in two kinds on a real rig, and a single median hides it:
% most are fast, and a share run several times slower in every phase at once.
% A boundary is called slow when its wait is over SlowFactor times the lower
% quartile, which stays put even when half of them are slow.
%
% Parameters:
%   S - results struct from bench_rig_preview, or the .mat it saved.
%
% Name=Value options:
%   Warmup     - leading boundaries left out of every summary. Default 5
%   BlockSize  - trials per block in the over-the-session table. Default 50
%   SlowFactor - see above. Default 2.5
%   Quiet      - no printed report. Default false
%
% Returns a struct:
%   N, NumSlow         - boundaries summarized, and how many were slow
%   Fast, Slow, All    - structs of medians (ms): Waited, Tick, Hold, Blocked,
%                        and one field per epsych.TickStats phase
%   Blocks             - table, one row per block of fast boundaries
%   PerTrial           - table, one row per boundary: Waited, Tick, Hold, Slow,
%                        and every phase (ms)
%
% See also: bench_rig_preview, bench_rig_tick, epsych.TickStats

arguments
    S
    options.Warmup (1,1) double {mustBeNonnegative, mustBeInteger} = 5
    options.BlockSize (1,1) double {mustBePositive, mustBeInteger} = 50
    options.SlowFactor (1,1) double {mustBePositive} = 2.5
    options.Quiet (1,1) logical = false
end
if ~isstruct(S)
    S = load(S);
end
say = ~options.Quiet;

% --- one row per timed boundary ----------------------------------------------
n = min([S.NumTrials, S.NumTimed, size(S.Phase, 1)]);
names = S.PhaseNames;
P = S.Phase(1:n, :) * 1e3;
P(:, all(isnan(P), 1)) = 0;
P(isnan(P)) = 0;
waited = sum(P(:, 1:find(names == "trigger")), 2);

T = S.Ticks;
isB = [T.nDone(1) > 0; diff(T.nDone) > 0];
bt = find(isB);
bt = bt(1:min(n, numel(bt)));
gap = [(T.tStart(2:end) - T.tStop(1:end-1)) * 1e3; NaN];      % after each tick
usual = median(gap(~isB), 'omitnan');
tick = nan(n, 1);
hold = nan(n, 1);
tick(1:numel(bt)) = (T.tStop(bt) - T.tStart(bt)) * 1e3;
hold(1:numel(bt)) = gap(bt) - usual;

use = false(n, 1);
use(options.Warmup + 1:n) = true;
slow = false(n, 1);
if any(use)
    slow(use) = waited(use) > options.SlowFactor * prctile(waited(use), 25);
end
PerTrial = array2table([waited, tick, hold, P], 'VariableNames', ["Waited" "Tick" "Hold" names]);
PerTrial.Slow = slow;

R = struct('N', sum(use), 'NumSlow', sum(slow), 'PerTrial', PerTrial);
R.Fast = localMedians(PerTrial(use & ~slow, :));
R.Slow = localMedians(PerTrial(use & slow, :));
R.All = localMedians(PerTrial(use, :));

edges = options.Warmup:options.BlockSize:n;
if edges(end) < n, edges(end+1) = n; end
rows = cell(numel(edges) - 1, 1);
for k = 1:numel(edges) - 1
    ix = false(n, 1);
    ix(edges(k) + 1:edges(k + 1)) = true;
    m = localMedians(PerTrial(ix & ~slow, :));
    rows{k} = table(edges(k) + 1, edges(k + 1), sum(ix & ~slow), sum(ix & slow), m.Waited, m.newData, m.render, ...
        m.writes, m.Hold, 'VariableNames', ["First" "Last" "NumFast" "NumSlow" "Waited" "newData" "render" "writes" "Hold"]);
end
R.Blocks = vertcat(rows{:});

if ~say, return; end

% --- report -------------------------------------------------------------------
fprintf('\n=== bench_rig_preview: %s ===\n', S.Outcome);
if isfield(S, 'Info')
    fprintf('%s, %s (%s), commit %.8s, R%s\n', S.Info.Subject, localFile(S.Info.Protocol), ...
        S.Info.ProtocolVersion, S.Info.Commit, S.Info.Release);
    fprintf('behavior GUI %s; saving function replaced (was %s)\n', S.Info.BehaviorGUI, S.Info.SavingFcn);
end
fprintf('%d trials in %.0f s (%d timed, %d under the profiler); timer period %.0f ms; displays deferred: %d\n', ...
    S.NumTrials, S.Elapsed, n, S.NumTrials - n, S.Meta.TimerPeriod * 1e3, S.Meta.DeferralEnabled);

if isfield(S, 'Data') && isfield(S.Data, 'RespCode')
    B = epsych.BitMask.decode(S.Data.RespCode);
    fprintf('outcomes: %d hits, %d misses, %d correct rejects, %d false alarms, %d aborts', ...
        sum(B.Hit), sum(B.Miss), sum(B.CorrectReject), sum(B.FalseAlarm), sum(B.Abort));
    if isfield(S.Data, 'PelletTotal')
        fprintf('; %g pellets', S.Data.PelletTotal(end));
    end
    fprintf('; a trial every %.1f s\n', median(seconds(diff(S.Data.Time))));
end

fprintf('\nAfter the first %d, %d of %d boundaries were slow (%.0f%%). Medians, ms:\n', ...
    options.Warmup, R.NumSlow, R.N, 100 * R.NumSlow / max(R.N, 1));
fprintf('  %-12s %9s %9s\n', '', 'fast', 'slow');
for f = ["Waited" names(any(P(use, :) > 0, 1)) "Tick" "Hold" "Blocked"]
    fprintf('  %-12s %9.1f %9.1f\n', f, R.Fast.(f), R.Slow.(f));
end
fprintf('  Waited is the sum of the phases through "trigger"; Blocked = Tick + Hold.\n');
fprintf('  Over all %d: waited median %.0f, mean %.0f, 95th percentile %.0f ms.\n', R.N, R.All.Waited, ...
    mean(waited(use)), prctile(waited(use), 95));
fprintf('  Warm-up, waited: %s ms\n', strjoin(compose('%.0f', waited(1:min(options.Warmup, n))), ', '));

fprintf('\nOver the session (fast boundaries, medians, ms):\n');
fprintf('  %-10s %6s %6s %8s %8s %8s %8s %8s\n', 'trials', 'fast', 'slow', 'waited', 'newData', 'render', 'writes', 'hold');
for k = 1:height(R.Blocks)
    b = R.Blocks(k, :);
    fprintf('  %4d-%-5d %6d %6d %8.1f %8.1f %8.1f %8.1f %8.0f\n', b.First, b.Last, b.NumFast, b.NumSlow, ...
        b.Waited, b.newData, b.render, b.writes, b.Hold);
end

idle = (T.tStop(~isB) - T.tStart(~isB)) * 1e3;
fprintf('\nBetween trials: an idle tick takes %.2f ms (95th percentile %.2f); %d of %d ran over the period.\n', ...
    median(idle), prctile(idle, 95), sum(idle > S.Meta.TimerPeriod * 1e3), numel(idle));

if isfield(S, 'Profile') && S.NumTrials > n
    localProfile(S.Profile, S.NumTrials - n);
end
if isfield(S, 'Info') && isfield(S.Info, 'OutFile')
    fprintf('\nResults: %s\n', S.Info.OutFile);
end
end


function m = localMedians(T)
% Median of every numeric column, plus Blocked = Tick + Hold.
m = struct();
for v = string(T.Properties.VariableNames)
    if v == "Slow", continue; end
    m.(v) = median(T.(v), 'omitnan');
end
m.Blocked = median(T.Tick + T.Hold, 'omitnan');
end


function localProfile(F, numTrials)
% The profiled trials, per trial. The profiler slows what it measures --
% roughly threefold here -- so read these as shares, not as milliseconds.
ours = ~contains(string({F.FunctionName}), ["bench_rig" "RigPreviewSubject" "timer.timercb" "TickStats"]);
F = F(ours);
[~, ix] = sort([F.SelfTime], 'descend');
fprintf('\nProfiler over the last %d trials, ms per trial (its own overhead included):\n', numTrials);
fprintf('  %-66s %8s %8s %7s\n', 'most self time', 'self', 'total', 'calls');
for k = ix(1:min(25, numel(ix)))
    fprintf('  %-66s %8.2f %8.2f %7.1f\n', localClip(F(k).FunctionName, 66), F(k).SelfTime * 1e3 / numTrials, ...
        F(k).TotalTime * 1e3 / numTrials, F(k).NumCalls / numTrials);
end
end


function s = localClip(s, n)
s = char(s);
s = s(1:min(n, end));
end


function s = localFile(f)
[~, s] = fileparts(char(f));
end
