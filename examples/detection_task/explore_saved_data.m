function R = explore_saved_data(datafile)
% R = explore_saved_data(datafile)
% Load a saved EPsych session file, decode the response codes, and summarize
% behavior: outcome counts, hit rate and d' per stimulus level, and a
% three-panel session figure (trial timeline, psychometric function, d').
%
% Works on any session whose DATA records carry RespCode (epsych.BitMask
% codes with TrialType_0 = go, TrialType_1 = catch) and ToneLevel; run
% run_detection_session.m to generate one.
%
% Parameters:
%   datafile - Path to a session .mat (variables Data and, optionally, Info).
%              Default: the newest .mat under data/ in this folder.
%
% Returns:
%   R - Results struct: datafile, nTrials, levels, nGo, nScored, hitRate,
%       faRate, dprime, and the decoded flag struct M. nGo counts every go
%       trial at a level; nScored counts the ones the subject answered, and
%       is the denominator behind hitRate.
%
% Walkthrough: documentation/examples/Detection_Task_5_Data.md
%
% See also run_detection_session, epsych.BitMask, psychophysics.Detection

arguments
    datafile (1,:) char = ''
end

here = fileparts(mfilename('fullpath'));
if isempty(datafile)
    d = dir(fullfile(here, 'data', '*.mat'));
    assert(~isempty(d), ...
        'No session files in %s - run run_detection_session first.', ...
        fullfile(here, 'data'))
    [~, newest] = max([d.datenum]);
    datafile = fullfile(d(newest).folder, d(newest).name);
end

S = load(datafile);
assert(isfield(S, 'Data'), 'Expected a "Data" variable in %s', datafile)
DATA = S.Data;
assert(all(isfield(DATA, {'RespCode', 'ToneLevel'})), ...
    'This session lacks the RespCode/ToneLevel fields this example analyzes.')

% --- Session facts -------------------------------------------------------
% The DATA array index is chronological order. DATA.TrialID is the row of
% the compiled condition list that was presented - a condition label, NOT
% the presentation order. Sort/iterate by array index, never by TrialID.
fprintf('\nSession file : %s\n', datafile)
fprintf('Trials       : %d\n', numel(DATA))
t = [DATA.computerTimestamp];
fprintf('Time span    : %s to %s\n', string(t(1)), string(t(end)))
if isfield(S, 'Info')
    % Info is a session snapshot since 2026-08 (epsych.SessionSnapshot), which
    % nests the repository metadata this used to read flat. fromInfo normalizes
    % both shapes, so an old file and a new one print the same line.
    meta = epsych.SessionSnapshot.fromInfo(S.Info).EPsychMeta;
    if isfield(meta, 'Version')
        fprintf('EPsych       : %s (commit %.7s)\n', meta.Version, meta.Checksum)
    end
end
if any([DATA.isTest])
    fprintf('NOTE         : flagged as test data (preview/simulated session)\n')
end

% --- Decode outcomes -----------------------------------------------------
% RespCode packs the whole trial outcome into one uint32; decode() expands
% it to one logical-array field per epsych.BitMask member.
rc = uint32([DATA.RespCode]);
M  = epsych.BitMask.decode(rc);

lvl    = [DATA.ToneLevel];
goIdx  = M.TrialType_0;
ctIdx  = M.TrialType_1;

fprintf('\nOutcome counts\n')
fprintf('  Go trials    : %3d  (%d hits, %d misses)\n', ...
    sum(goIdx), sum(M.Hit), sum(M.Miss))
fprintf('  Catch trials : %3d  (%d false alarms, %d correct rejects)\n', ...
    sum(ctIdx), sum(M.FalseAlarm), sum(M.CorrectReject))

% --- Performance per stimulus level --------------------------------------
% Rates count the trials the subject answered. An abort is a lapse of
% engagement rather than a wrong answer, so it is left out of the denominator
% by default; pass true below to score aborts as failures to respond instead.
% psychophysics.Metrics.rateDenominator is where that convention lives, and
% every analysis class in the toolbox takes the same IncludeAborts option.
includeAborts = false;

nCatchScored = psychophysics.Metrics.rateDenominator( ...
    sum(M.FalseAlarm & ctIdx) + sum(M.CorrectReject & ctIdx), ...
    sum(M.Abort & ctIdx), includeAborts);
faRate = psychophysics.Metrics.rate(sum(M.FalseAlarm & ctIdx), nCatchScored);

levels   = unique(lvl(goIdx));
nGo      = zeros(size(levels));   % every go trial at that level
nScored  = zeros(size(levels));   % ...of which the subject answered
hitRate  = zeros(size(levels));
for k = 1:numel(levels)
    ind         = goIdx & lvl == levels(k);
    nGo(k)      = sum(ind);
    nScored(k)  = psychophysics.Metrics.rateDenominator( ...
        sum(M.Hit & ind) + sum(M.Miss & ind), sum(M.Abort & ind), includeAborts);
    hitRate(k)  = psychophysics.Metrics.rate(sum(M.Hit & ind), nScored(k));
end

% d' from hit rate per level against the session-wide catch false-alarm rate.
% A level where every trial was a hit would send the z-transform to infinity,
% so the log-linear correction pulls the rates in by half a trial -- which is
% why the trial counts travel alongside the rates, and why a level with 8
% trials is corrected harder than one with 80.
dprime = psychophysics.Metrics.dprime(hitRate, faRate, ...
    Correction="loglinear", NSignal=nScored, NNoise=nCatchScored);

fprintf('\n  Level (dB SPL)   # Go   # Answered   Hit rate     d''\n')
for k = 1:numel(levels)
    fprintf('  %10g       %4d         %4d      %5.2f   %6.2f\n', ...
        levels(k), nGo(k), nScored(k), hitRate(k), dprime(k))
end
fprintf('  Catch FA rate: %.2f  (%d of %d catch trials answered)\n\n', ...
    faRate, nCatchScored, sum(ctIdx))

% --- Session figure ------------------------------------------------------
fig = figure(Name = 'EPsych session summary', Color = 'w', ...
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
    h = scatter(ax, trialNum(ind), lvl(ind), 36, ...
        Marker = markers{k}, MarkerEdgeColor = clr(k), ...
        LineWidth = 1.25, DisplayName = char(outcomes(k)));
    if ~strcmp(markers{k}, 'x')
        h.MarkerFaceColor = clr(k);
        h.MarkerFaceAlpha = 0.35;
    end
end
hold(ax, 'off')
xlabel(ax, 'Trial (presentation order)')
ylabel(ax, 'Tone level (dB SPL)')
title(ax, 'Trial timeline')
legend(ax, Location = 'northoutside', Orientation = 'horizontal', Box = 'off')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

lineColor = [0.13 0.35 0.70];
refColor  = [0.45 0.45 0.45];

% 2. Psychometric function
ax = nexttile(tl);
plot(ax, levels, hitRate, '-o', Color = lineColor, LineWidth = 2, ...
    MarkerFaceColor = lineColor, MarkerSize = 7)
yline(ax, faRate, '--', 'catch FA rate', Color = refColor, ...
    LabelHorizontalAlignment = 'left')
ylim(ax, [0 1]); xticks(ax, levels)
xlabel(ax, 'Tone level (dB SPL)')
ylabel(ax, 'Hit rate')
title(ax, 'Psychometric function')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

% 3. Sensitivity
ax = nexttile(tl);
plot(ax, levels, dprime, '-o', Color = lineColor, LineWidth = 2, ...
    MarkerFaceColor = lineColor, MarkerSize = 7)
yline(ax, 1, '--', 'd'' = 1', Color = refColor, ...
    LabelHorizontalAlignment = 'left')
xticks(ax, levels)
xlabel(ax, 'Tone level (dB SPL)')
ylabel(ax, 'd''')
title(ax, 'Sensitivity')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

R = struct('datafile', datafile, 'nTrials', numel(DATA), 'levels', levels, ...
    'nGo', nGo, 'nScored', nScored, 'hitRate', hitRate, 'faRate', faRate, ...
    'dprime', dprime, 'M', M);

if nargout == 0, clear R; end
