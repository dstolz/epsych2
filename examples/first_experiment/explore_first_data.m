function R = explore_first_data(datafile)
% R = explore_first_data(datafile)
% Load a session saved by the first-experiment tutorial, decode the
% response codes, and summarize YOUR behavior: outcome counts, hit rate
% and d' per flash duration, and a session figure (trial timeline,
% psychometric function, reaction times).
%
% Works on any session whose DATA records carry RespCode (epsych.BitMask
% codes with TrialType_0 = go, TrialType_1 = catch), FlashDur, and RT_ms;
% run run_first_experiment (or the RunExpt walkthrough) to generate one.
%
% Parameters:
%   datafile - Path to a session .mat (variables Data and, optionally,
%              Info). Default: the newest .mat under data/ in this folder.
%
% Returns:
%   R - Results struct: datafile, nTrials, durations, nGo, hitRate,
%       faRate, dprime, medianRT, and the decoded flag struct M.
%
% Walkthrough: https://github.com/dstolz/epsych2/wiki/Your-First-Experiment
%
% See also run_first_experiment, epsych.BitMask, psychophysics.Detection

arguments
    datafile (1,:) char = ''
end

here = fileparts(mfilename('fullpath'));
if isempty(datafile)
    d = dir(fullfile(here, 'data', '**', '*.mat'));
    d = d(~startsWith({d.name}, 'RUNTIME_DATA_')); % skip crash-recovery seeds
    assert(~isempty(d), ...
        'No session files under %s - run run_first_experiment first.', ...
        fullfile(here, 'data'))
    [~, newest] = max([d.datenum]);
    datafile = fullfile(d(newest).folder, d(newest).name);
end

S = load(datafile);
assert(isfield(S, 'Data'), 'Expected a "Data" variable in %s', datafile)
DATA = S.Data;
assert(all(isfield(DATA, {'RespCode', 'FlashDur', 'RT_ms'})), ...
    'This session lacks the RespCode/FlashDur/RT_ms fields this example analyzes.')

% --- Session facts -------------------------------------------------------
% The DATA array index is chronological order. DATA.TrialID is the row of
% the compiled condition list that was presented - a condition label, NOT
% the presentation order. Sort/iterate by array index, never by TrialID.
fprintf('\nSession file : %s\n', datafile)
fprintf('Trials       : %d\n', numel(DATA))
t = [DATA.computerTimestamp];
fprintf('Time span    : %s to %s\n', string(t(1)), string(t(end)))
if isfield(S, 'Info')
    fprintf('EPsych       : %s (commit %.7s)\n', S.Info.Version, S.Info.Checksum)
end
if any([DATA.isTest])
    fprintf('NOTE         : flagged as test data (preview session)\n')
end

% --- Decode outcomes -----------------------------------------------------
% RespCode packs the whole trial outcome into one uint32; decode() expands
% it to one logical-array field per epsych.BitMask member.
rc = uint32([DATA.RespCode]);
M  = epsych.BitMask.decode(rc);

dur   = [DATA.FlashDur];
rt    = [DATA.RT_ms];
goIdx = M.TrialType_0;
ctIdx = M.TrialType_1;

fprintf('\nOutcome counts\n')
fprintf('  Go trials    : %3d  (%d hits, %d misses)\n', ...
    sum(goIdx), sum(M.Hit), sum(M.Miss))
fprintf('  Catch trials : %3d  (%d false alarms, %d correct rejects)\n', ...
    sum(ctIdx), sum(M.FalseAlarm), sum(M.CorrectReject))

% --- Performance per flash duration --------------------------------------
faRate = sum(M.FalseAlarm & ctIdx) / max(1, sum(ctIdx));

durations = unique(dur(goIdx));
nGo      = zeros(size(durations));
hitRate  = zeros(size(durations));
medianRT = nan(size(durations));
for k = 1:numel(durations)
    ind        = goIdx & dur == durations(k);
    nGo(k)     = sum(ind);
    hitRate(k) = sum(M.Hit & ind) / nGo(k);
    hitsHere   = M.Hit & ind & isfinite(rt);
    if any(hitsHere), medianRT(k) = median(rt(hitsHere)); end
end

% d' from hit rate per duration against the session-wide catch
% false-alarm rate, with the same finite corrections the online tools use.
dprime = arrayfun(@(h) psychophysics.Detection.d_prime(h, faRate), hitRate);

fprintf('\n  Flash (ms)   # Go   Hit rate     d''   median RT (ms)\n')
for k = 1:numel(durations)
    fprintf('  %8g     %4d      %5.2f   %6.2f   %8g\n', ...
        durations(k), nGo(k), hitRate(k), dprime(k), medianRT(k))
end
fprintf('  Catch FA rate: %.2f\n\n', faRate)

% --- Session figure ------------------------------------------------------
fig = figure(Name = 'Your first EPsych session', Color = 'w', ...
    Position = [100 100 950 700]);
tl = tiledlayout(fig, 2, 2, TileSpacing = 'compact', Padding = 'compact');
[~, fn] = fileparts(datafile);
title(tl, fn, Interpreter = 'none')

% Outcome colors follow the toolbox-wide convention; marker shape encodes
% the outcome too, so identity never rides on color alone.
outcomes = [epsych.BitMask.Hit, epsych.BitMask.Miss, ...
    epsych.BitMask.FalseAlarm, epsych.BitMask.CorrectReject];
clr     = epsych.BitMask.getDefaultColors(outcomes);
markers = {'o', 'x', '^', 's'};

% 1. Trial timeline: every trial in presentation order
ax = nexttile(tl, [1 2]);
hold(ax, 'on')
trialNum = 1:numel(DATA);
for k = 1:numel(outcomes)
    ind = M.(char(outcomes(k)));
    h = scatter(ax, trialNum(ind), dur(ind), 36, ...
        Marker = markers{k}, MarkerEdgeColor = clr(k), ...
        LineWidth = 1.25, DisplayName = char(outcomes(k)));
    if ~strcmp(markers{k}, 'x')
        h.MarkerFaceColor = clr(k);
        h.MarkerFaceAlpha = 0.35;
    end
end
hold(ax, 'off')
xlabel(ax, 'Trial (presentation order)')
ylabel(ax, 'Flash duration (ms)')
title(ax, 'Trial timeline')
legend(ax, Location = 'northoutside', Orientation = 'horizontal', Box = 'off')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

lineColor = [0.13 0.35 0.70];
refColor  = [0.45 0.45 0.45];

% 2. Psychometric function
ax = nexttile(tl);
plot(ax, durations, hitRate, '-o', Color = lineColor, LineWidth = 2, ...
    MarkerFaceColor = lineColor, MarkerSize = 7)
yline(ax, faRate, '--', 'catch FA rate', Color = refColor, ...
    LabelHorizontalAlignment = 'left')
ylim(ax, [0 1]); xticks(ax, durations)
xlabel(ax, 'Flash duration (ms)')
ylabel(ax, 'Hit rate')
title(ax, 'Psychometric function')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

% 3. Reaction time on hits
ax = nexttile(tl);
hold(ax, 'on')
hitInd = M.Hit & isfinite(rt);
scatter(ax, dur(hitInd), rt(hitInd), 30, ...
    MarkerEdgeColor = lineColor, MarkerFaceColor = lineColor, ...
    MarkerFaceAlpha = 0.3, HandleVisibility = 'off')
plot(ax, durations, medianRT, '-o', Color = [0.75 0.2 0.15], LineWidth = 2, ...
    MarkerFaceColor = [0.75 0.2 0.15], MarkerSize = 7, DisplayName = 'median')
hold(ax, 'off')
xticks(ax, durations)
xlabel(ax, 'Flash duration (ms)')
ylabel(ax, 'Reaction time (ms)')
title(ax, 'Reaction time (hits)')
legend(ax, Location = 'northeast', Box = 'off')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

R = struct('datafile', datafile, 'nTrials', numel(DATA), ...
    'durations', durations, 'nGo', nGo, 'hitRate', hitRate, ...
    'faRate', faRate, 'dprime', dprime, 'medianRT', medianRT, 'M', M);

if nargout == 0, clear R; end
