function R = explore_2afc_data(datafile)
% R = explore_2afc_data(datafile)
% Load a session saved by the 2AFC tutorial, decode the response codes,
% and summarize YOUR behavior: accuracy per difficulty, the choice curve
% P(chose right) against signed contrast with a fitted cumulative
% Gaussian, the point of subjective equality (your side bias), the
% just-noticeable difference, and reaction times.
%
% Two analyses of the same file run side by side: one hand-rolled from the
% decoded bits, and one from psychophysics.NAFC, which produces percent
% correct against a 1/N chance level and the per-alternative choice bias.
% They should agree.
%
% Works on any session whose DATA records carry RespCode (epsych.BitMask
% codes: Choice_k for the alternative chosen, Hit when it was correct and
% Miss when it was not, Abort for an answer before the response window,
% and no outcome bit at all when the trial lapsed), TrialType, Contrast,
% ChoiceSide, and RT_ms.
%
% Parameters:
%   datafile - Path to a session .mat (variables Data and, optionally,
%              Info). Default: the newest .mat under data/ in this folder.
%
% Returns:
%   R - Results struct: datafile, nTrials, nNoResponse, nAborted,
%       signedLevels, pRight, contrasts, accuracy, pse, jnd, pctCorrect,
%       choiceBias, medianRT, and the decoded flag struct M.
%
% Walkthrough: https://github.com/dstolz/epsych2/wiki/Two-AFC-Task
%
% See also run_2afc_experiment, epsych.BitMask, psychophysics.NAFC

arguments
    datafile (1,:) char = ''
end

here = fileparts(mfilename('fullpath'));
if isempty(datafile)
    d = dir(fullfile(here, 'data', '**', '*.mat'));
    d = d(~startsWith({d.name}, 'RUNTIME_DATA_')); % skip crash-recovery seeds
    assert(~isempty(d), ...
        'No session files under %s - run run_2afc_experiment first.', ...
        fullfile(here, 'data'))
    [~, newest] = max([d.datenum]);
    datafile = fullfile(d(newest).folder, d(newest).name);
end

S = load(datafile);
assert(isfield(S, 'Data'), 'Expected a "Data" variable in %s', datafile)
DATA = S.Data;
assert(all(isfield(DATA, {'RespCode', 'TrialType', 'Contrast', 'ChoiceSide', 'RT_ms'})), ...
    'This session lacks the fields this example analyzes.')

% --- Session facts -------------------------------------------------------
% The DATA array index is chronological order. DATA.TrialID is the row of
% the compiled condition list that was presented - a condition label, NOT
% the presentation order.
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
    fprintf('NOTE         : flagged as test data (preview session)\n')
end

% --- Decode outcomes -----------------------------------------------------
% RespCode packs the whole trial outcome into one uint32; decode() expands
% it to one logical-array field per epsych.BitMask member. Choice_1 marks
% a rightward choice whether or not it was correct - that separation of
% "what was chosen" (Choice_*) from "was it right" (Hit / Miss) is what a
% forced choice needs, and the reason both are recorded. In an N-AFC every
% alternative is a response, so no outcome name carries the side and
% CorrectReject / FalseAlarm are never set: those are detection outcomes.
rc = uint32([DATA.RespCode]);
M  = epsych.BitMask.decode(rc);

side     = [DATA.TrialType];           % 0 = left correct, 1 = right correct
contrast = [DATA.Contrast];
choice   = [DATA.ChoiceSide];          % 0 = left, 1 = right, -1 = no answer
rt       = [DATA.RT_ms];               % -1 when the trial was not answered
signed   = contrast .* (2 * side - 1); % negative = left lamp brighter

answered = choice >= 0;
correct  = M.Hit;                      % correct is Hit, and only Hit

% Two ways to leave a trial unanswered, and the bits keep them apart: an
% Abort answered too early, while a lapsed trial carries no outcome bit at
% all. getResponses() is the list of outcome bits, so "none of them set"
% is Undefined without hardcoding which names exist.
outcomes = string(epsych.BitMask.getResponses());
scored   = false(size(rc));
for k = 1:numel(outcomes), scored = scored | M.(outcomes(k)); end
noResponse = ~scored;

fprintf('\nOutcome counts\n')
fprintf('  Answered     : %3d  (%d correct, %d incorrect)\n', ...
    sum(answered), sum(correct), sum(M.Miss))
fprintf('  No response  : %3d  (window lapsed; Undefined - no outcome bit)\n', sum(noResponse))
fprintf('  Aborted      : %3d  (answered before the response window opened)\n', sum(M.Abort))
fprintf('  Chose right  : %3d of %d answered (%.0f%%)\n', ...
    sum(M.Choice_1), sum(answered), 100 * sum(M.Choice_1) / max(1, sum(answered)))

% --- Accuracy per difficulty ---------------------------------------------
contrasts = unique(contrast);
accuracy  = nan(size(contrasts));
nPerLevel = zeros(size(contrasts));
for k = 1:numel(contrasts)
    ind = answered & contrast == contrasts(k);
    nPerLevel(k) = sum(ind);
    if nPerLevel(k) > 0
        accuracy(k) = mean(correct(ind));
    end
end

fprintf('\n  Contrast     n   %% correct   median RT (ms)\n')
for k = 1:numel(contrasts)
    ind = answered & contrast == contrasts(k) & rt >= 0;
    fprintf('  %8.2f  %4d      %5.0f   %8g\n', contrasts(k), nPerLevel(k), ...
        100 * accuracy(k), median(rt(ind)))
end

% --- The choice curve ----------------------------------------------------
% P(chose right) against SIGNED contrast is the 2AFC psychometric
% function. Where it crosses 50% is the point of subjective equality: the
% stimulus the subject finds ambiguous, and therefore their side bias.
signedLevels = unique(signed);
pRight = nan(size(signedLevels));
nRight = zeros(size(signedLevels));
for k = 1:numel(signedLevels)
    ind = answered & signed == signedLevels(k);
    nRight(k) = sum(ind);
    if nRight(k) > 0
        pRight(k) = mean(choice(ind) == 1);
    end
end

[pse, jnd, fitFcn] = fitChoiceCurve(signedLevels, pRight, nRight);
if isfinite(pse)
    fprintf('\n  Point of subjective equality : %+.3f contrast units', pse)
    if abs(pse) < 0.01
        fprintf('   (no meaningful side bias)\n')
    elseif pse > 0
        fprintf('   (bias toward answering LEFT)\n')
    else
        fprintf('   (bias toward answering RIGHT)\n')
    end
    fprintf('  Just-noticeable difference   :  %.3f contrast units (84%% correct)\n', jnd)
else
    fprintf('\n  Choice-curve fit did not converge (too few trials or levels).\n')
end

% --- The same session through the toolbox --------------------------------
% psychophysics.NAFC is the analysis a forced choice belongs in, and it
% needs no trial-type arguments: correctness comes from comparing the
% chosen alternative with the correct one, never from the Hit/Miss bits.
% (psychophysics.SessionMetrics is deliberately NOT used here. Its hit
% rate, false-alarm rate, d' and criterion are built on a stimulus/catch
% split that a forced choice does not have.)
NA = psychophysics.NAFC(DATA, 'SignedContrast', NumAlternatives = 2, ...
    ChoiceField = "ChoiceSide", ChoiceLabels = ["Left", "Right"]);
NR = NA.Results;
fprintf('\npsychophysics.NAFC over the whole session\n')
fprintf('  Trials          : %d\n', NR.NumTrials)
fprintf('  Percent correct : %.1f%%  (chance %.0f%%)\n', ...
    100 * NR.PercentCorrect, 100 * NR.ChanceLevel)
fprintf('  Chose left      : %.1f%%   (bias %+.1f%% re chance)\n', ...
    100 * NR.ChoiceProportion(1), 100 * NR.ChoiceBias(1))
fprintf('  Chose right     : %.1f%%   (bias %+.1f%% re chance)\n', ...
    100 * NR.ChoiceProportion(2), 100 * NR.ChoiceBias(2))
fprintf('  No response     : %d\n', NR.NumNoResponse)
fprintf('  Aborted (early) : %d\n', NR.NumAborted)

% --- Session figure ------------------------------------------------------
fig = figure(Name = 'Your 2AFC session', Color = 'w', ...
    Position = [100 100 950 700]);
tl = tiledlayout(fig, 2, 2, TileSpacing = 'compact', Padding = 'compact');
[~, fn] = fileparts(datafile);
title(tl, fn, Interpreter = 'none')

lineColor = [0.13 0.35 0.70];
refColor  = [0.45 0.45 0.45];

% 1. Trial timeline: signed contrast, marker shape by outcome
ax = nexttile(tl, [1 2]);
hold(ax, 'on')
trialNum = 1:numel(DATA);
groups = {correct, M.Miss, noResponse, M.Abort};
labels = {'Correct', 'Incorrect', 'No response', 'Aborted'};
clr = epsych.BitMask.getDefaultColors([epsych.BitMask.Hit, ...
    epsych.BitMask.Miss, epsych.BitMask.Undefined, epsych.BitMask.Abort]);
markers = {'o', 'x', 's', 'd'};
for k = 1:numel(groups)
    ind = groups{k};
    if ~any(ind), continue; end
    h = scatter(ax, trialNum(ind), signed(ind), 36, ...
        Marker = markers{k}, MarkerEdgeColor = clr(k), ...
        LineWidth = 1.25, DisplayName = labels{k});
    if ~strcmp(markers{k}, 'x')
        h.MarkerFaceColor = clr(k);
        h.MarkerFaceAlpha = 0.35;
    end
end
yline(ax, 0, '-', Color = refColor)
hold(ax, 'off')
xlabel(ax, 'Trial (presentation order)')
ylabel(ax, 'Signed contrast')
title(ax, 'Trial timeline (negative = left lamp brighter)')
legend(ax, Location = 'northoutside', Orientation = 'horizontal', Box = 'off')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

% 2. Choice curve with the fit and the PSE
ax = nexttile(tl);
hold(ax, 'on')
if ~isempty(fitFcn)
    xx = linspace(min(signedLevels), max(signedLevels), 200);
    plot(ax, xx, fitFcn(xx), '-', Color = lineColor, LineWidth = 2, ...
        DisplayName = 'cumulative Gaussian')
end
scatter(ax, signedLevels, pRight, 40, MarkerEdgeColor = lineColor, ...
    MarkerFaceColor = lineColor, MarkerFaceAlpha = 0.45, DisplayName = 'data')
yline(ax, 0.5, '--', Color = refColor, HandleVisibility = 'off')
if isfinite(pse)
    xline(ax, pse, ':', sprintf('PSE %+.3f', pse), Color = [0.75 0.2 0.15], ...
        LineWidth = 1.5, LabelVerticalAlignment = 'bottom', HandleVisibility = 'off')
end
hold(ax, 'off')
ylim(ax, [0 1])
xlabel(ax, 'Signed contrast (negative = left brighter)')
ylabel(ax, 'P(chose right)')
title(ax, 'Choice curve')
legend(ax, Location = 'southeast', Box = 'off')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

% 3. Accuracy against difficulty, with the chance line a 2AFC has and a
%    yes/no task does not: guessing scores 50%, not 0%.
ax = nexttile(tl);
plot(ax, contrasts, accuracy, '-o', Color = lineColor, LineWidth = 2, ...
    MarkerFaceColor = lineColor, MarkerSize = 7)
yline(ax, 0.5, '--', 'chance', Color = refColor, LabelHorizontalAlignment = 'left')
ylim(ax, [0 1]); xticks(ax, contrasts)
xlabel(ax, 'Contrast (unsigned difficulty)')
ylabel(ax, 'Proportion correct')
title(ax, 'Accuracy by difficulty')
grid(ax, 'on'); ax.GridAlpha = 0.12; ax.Box = 'off';

R = struct('datafile', datafile, 'nTrials', numel(DATA), ...
    'nNoResponse', sum(noResponse), 'nAborted', sum(M.Abort), ...
    'signedLevels', signedLevels, 'pRight', pRight, ...
    'contrasts', contrasts, 'accuracy', accuracy, 'pse', pse, 'jnd', jnd, ...
    'pctCorrect', NR.PercentCorrect, 'choiceBias', NR.ChoiceBias, ...
    'medianRT', median(rt(answered & rt >= 0)), 'M', M);

if nargout == 0, clear R; end
end


function [pse, jnd, fitFcn] = fitChoiceCurve(x, p, n)
% Fit P(chose right) = normcdf((x - mu)/sigma) by maximum likelihood.
% mu is the point of subjective equality (the 50% point, i.e. the side
% bias) and sigma the just-noticeable difference. Returns NaN and an empty
% function handle when there is not enough data to constrain a fit.
pse = NaN; jnd = NaN; fitFcn = [];

ok = n > 0 & isfinite(p);
x = x(ok); p = p(ok); n = n(ok);
if numel(x) < 3 || numel(unique(p)) < 2, return; end

k = round(p .* n); % rightward choices per level
nll = @(q) -sum(k .* log(max(pr(x, q), eps)) + ...
    (n - k) .* log(max(1 - pr(x, q), eps)));

q0 = [0, max(std(x), eps)];
opts = optimset('Display', 'off');
try
    q = fminsearch(nll, q0, opts);
catch
    return
end

if ~all(isfinite(q)) || q(2) <= 0, return; end
pse = q(1);
jnd = abs(q(2));
fitFcn = @(xx) pr(xx, q);
end


function y = pr(x, q)
% Cumulative-Gaussian choice probability with mean q(1) and sd q(2).
y = normcdf((x - q(1)) ./ max(abs(q(2)), eps));
end
