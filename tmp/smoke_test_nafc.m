function smoke_test_nafc
% smoke_test_nafc
% Exercises psychophysics.NAFC against a hand-built 3AFC session whose
% every count is known, then the alternate data routes (choice from a DATA
% field vs Choice_* bits, correct from the TrialType field vs TrialType_*
% bits), fixed and auto-detected NumAlternatives, exclusions, the three
% plot types with their pop-out, and online mode over a fake runtime.
% Headless-safe.
%
% Verifies:
%   1) session and by-value statistics match hand counts: trials, aborts,
%      percent correct, choice rates, choice bias, confusion matrix
%   2) the four data routes agree: Choice_* bits == ChoiceField, and
%      TrialType field == TrialType_* bits fallback
%   3) NumAlternatives: auto-detect finds N=3; fixing N=4 rescales chance
%      and pads the matrices; fixing N=2 quarantines out-of-range trials
%      in NumInvalid instead of silently rescaling chance
%   4) ExcludedTrials drops a trial from every statistic
%   5) ChoiceLabels/ChoiceColors pad to N; plotting draws all three
%      PlotTypes, survives PlotType switches, pops out (gui.PopOut),
%      disables cleanly, and survives its embedded axes being deleted
%   6) online mode: results and the plot follow NewData events, and
%      obj.Events re-broadcasts them
%
% Run headless: matlab -batch "run('tmp/smoke_test_nafc.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

cleanup = onCleanup(@() close(findall(groot, 'Type', 'figure')));

% Hand-built 3AFC session over Coherence = [0.1 0.2 0.4]. Columns:
% value, correct alternative, chosen alternative (NaN = no answer).
% The one deliberately wrong-at-0.1 trial sits LAST so the exclusion
% check below can drop it by index.
spec = [ ...
    0.1 0 0
    0.1 0 1
    0.1 1 2
    0.1 1 1
    0.1 2 0
    0.1 2 2
    0.1 0 NaN
    0.2 0 0
    0.2 0 0
    0.2 1 1
    0.2 1 0
    0.2 2 2
    0.2 2 2
    0.4 0 0
    0.4 1 1
    0.4 2 2
    0.4 0 0
    0.4 1 1
    0.4 2 2
    0.4 1 NaN
    0.1 0 2];
nTrials = size(spec, 1);

DATA = struct('RespCode', cell(1, nTrials));
for i = 1:nTrials
    c = spec(i,2); ch = spec(i,3);
    bits = epsych.BitMask("TrialType_" + c);
    if isnan(ch)
        bits(end+1) = epsych.BitMask.Abort;
        chField = -1;
    else
        bits(end+1) = epsych.BitMask("Choice_" + ch);
        chField = ch;
    end
    DATA(i).RespCode   = double(epsych.BitMask.Bits2Mask(uint32(bits)));
    DATA(i).TrialType  = c;
    DATA(i).Coherence  = spec(i,1);
    DATA(i).ChoiceResp = chField;
end

% 1. Hand counts ---------------------------------------------------------
A = psychophysics.NAFC(DATA, 'Coherence');
R = A.Results;
assert(R.NumAlternatives == 3 && abs(R.ChanceLevel - 1/3) < 1e-12, ...
    'auto-detect should find 3 alternatives, got %d', R.NumAlternatives);
assert(R.NumTrials == 21 && R.NumAnswered == 19 && R.NumAborted == 2 ...
    && R.NumInvalid == 0, 'session counts disagree with the hand count');
assert(abs(R.AbortRate - 2/21) < 1e-12, 'abort rate disagrees');
assert(abs(R.PercentCorrect - 14/19) < 1e-12, ...
    'percent correct %.4f, hand count says %.4f', R.PercentCorrect, 14/19);

assert(isequal(R.Values, [0.1 0.2 0.4]), 'unique values wrong: %s', mat2str(R.Values));
assert(isequal(R.NumByValue, [7 6 6]), 'answered-per-value wrong: %s', mat2str(R.NumByValue));
assert(isequal(R.ChoiceCount, [2 3 2; 2 1 2; 3 2 2]), ...
    'choice counts disagree: %s', mat2str(R.ChoiceCount));
assert(all(abs(sum(R.ChoiceRate, 1) - 1) < 1e-12), 'choice rates must sum to 1 per value');
assert(max(abs(R.CorrectRate - [3/7 5/6 1])) < 1e-12, ...
    'correct rate by value disagrees: %s', mat2str(R.CorrectRate));

assert(isequal(R.ChoiceTotals, [7 5 7]), 'overall choice totals disagree');
assert(abs(sum(R.ChoiceBias)) < 1e-12, 'choice bias must sum to zero');
assert(isequal(R.ConfusionCount, [5 1 1; 1 4 1; 1 0 5]), ...
    'confusion counts disagree: %s', mat2str(R.ConfusionCount));
assert(all(abs(sum(R.ConfusionRate, 2) - 1) < 1e-12), 'confusion rows must sum to 1');
assert(isequaln(R.IsCorrect(20:21), [NaN 0]), 'IsCorrect must be NaN on aborts');
fprintf('PASS: 3AFC hand counts (%.0f%% correct over %d answered)\n', ...
    100 * R.PercentCorrect, R.NumAnswered);

% 2. The data routes agree ----------------------------------------------
% Choice from the ChoiceResp field instead of Choice_* bits.
Afield = psychophysics.NAFC(DATA, 'Coherence', ChoiceField = "ChoiceResp");
assert(isequaln(Afield.Results, R), 'ChoiceField route must reproduce the bit route');

% Correct from TrialType_* bits when the TrialType field is missing.
Abits = psychophysics.NAFC(rmfield(DATA, 'TrialType'), 'Coherence');
assert(isequaln(Abits.Results, R), 'TrialType-bit fallback must reproduce the field route');
fprintf('PASS: field and bit data routes agree\n');

% 3. NumAlternatives -----------------------------------------------------
A4 = psychophysics.NAFC(DATA, 'Coherence', NumAlternatives = 4);
R4 = A4.Results;
assert(R4.NumAlternatives == 4 && abs(R4.ChanceLevel - 0.25) < 1e-12, 'fixed N=4 ignored');
assert(isequal(size(R4.ConfusionCount), [4 4]) && all(R4.ConfusionCount(4,:) == 0) ...
    && all(R4.ConfusionCount(:,4) == 0), 'N=4 must pad an empty fourth alternative');
assert(abs(R4.PercentCorrect - R.PercentCorrect) < 1e-12, ...
    'padding alternatives must not change percent correct');

A2 = psychophysics.NAFC(DATA, 'Coherence', NumAlternatives = 2);
R2 = A2.Results;
assert(R2.NumInvalid == 8, 'N=2 should quarantine 8 trials mentioning alternative 2, got %d', ...
    R2.NumInvalid);
assert(R2.NumTrials == 13 && R2.NumAnswered == 11, 'N=2 counts disagree');
assert(abs(R2.PercentCorrect - 9/11) < 1e-12, 'N=2 percent correct disagrees');
fprintf('PASS: fixed, padded, and quarantined NumAlternatives\n');

% 4. Exclusions ----------------------------------------------------------
A.ExcludedTrials = nTrials;  % the trailing wrong-at-0.1 trial
Rx = A.Results;
assert(Rx.NumTrials == 20 && Rx.NumAnswered == 18, 'exclusion did not drop the trial');
assert(abs(Rx.PercentCorrect - 14/18) < 1e-12, 'excluded trial still scored');
assert(max(abs(Rx.ChoiceRate(:,1) - 1/3)) < 1e-12, ...
    'value 0.1 should be perfectly balanced after the exclusion');
A.ExcludedTrials = [];
fprintf('PASS: ExcludedTrials drops the trial from every statistic\n');

% 5. Labels, colors, and the three plots ---------------------------------
A.ChoiceLabels = ["Left", "Center"];
labels = A.alternativeLabels();
assert(isequal(labels, ["Left", "Center", "Choice 2"]), ...
    'labels must pad to N: %s', strjoin(labels, ','));
colors = A.alternativeColors();
assert(numel(colors) == 3 && all(startsWith(colors, "#")), 'colors must pad to N hex values');

A.Plot();
fig = findall(groot, 'Type', 'figure', 'Name', '3AFC | Coherence');
assert(isscalar(fig), 'owned plot window not found');
ax = findall(fig, 'Type', 'axes');
assert(isscalar(ax) && ~isempty(ax.Children), 'choice plot never drew');
nChoice = numel(ax.Children);

A.PlotType = "performance";
assert(~isempty(ax.Children) && numel(ax.Children) ~= nChoice, ...
    'switching PlotType must redraw the axes');
A.PlotType = "confusion";
assert(any(arrayfun(@(h) isa(h, 'matlab.graphics.primitive.Image'), ax.Children)), ...
    'confusion plot must draw a heatmap image');
A.PlotType = "choice";

% Repeated refreshes must not accumulate graphics. The connecting curves and
% the chance line are HandleVisibility='off' so they cost no legend row,
% which also makes them invisible to ax.Children AND to cla -- this check
% uses allchild for that reason. Without it a leak here is unseeable: the
% markers update correctly while every refresh leaves its own curves behind,
% so an online session ends up drawing its whole history on top of itself.
nAll = numel(allchild(ax));
for k = 1:5, A.refreshPlot(); end
assert(numel(allchild(ax)) == nAll, ...
    'refreshPlot leaked graphics: %d objects after 5 more refreshes, %d after the first', ...
    numel(allchild(ax)), nAll);

p = A.popOut();
assert(isa(p, 'psychophysics.NAFC') && A.hasPopOut(), 'popOut must open a sibling NAFC');
assert(p.PlotType == "choice" && p.Results.NumAnswered == R.NumAnswered, ...
    'the pop-out must score the same trials');
A.closePopOut();
assert(~A.hasPopOut(), 'closePopOut left the window registered');

A.disablePlot();
assert(isempty(findall(groot, 'Type', 'figure', 'Name', '3AFC | Coherence')), ...
    'disablePlot must delete the owned window');

% Embedded axes: deleting the host figure must disable plotting, not error.
hostFig = uifigure('Name', 'smoke_test_nafc_host');
hax = uiaxes(hostFig);
A.Plot(hax, PlotType = "performance");
assert(~isempty(hax.Children), 'embedded plot never drew');
delete(hostFig);
A.refresh();  % must be a silent no-op for the plot
fprintf('PASS: labels, colors, three plot types, pop-out, teardown\n');

% 6. Online mode ---------------------------------------------------------
RT = NAFC_FakeRuntime;
Aon = psychophysics.NAFC(RT, struct('Name', 'Coherence', 'validName', 'Coherence'), ...
    ChoiceField = "ChoiceResp", Plot = true);
evCount = containers.Map('KeyType', 'char', 'ValueType', 'double');
evCount('n') = 0;
hl = addlistener(Aon.Events, 'NewData', @(~,~) bumpCounter(evCount));

RT.push(DATA(1:10));
assert(Aon.Results.NumTrials == 10, 'online mode missed the first NewData');
RT.push(DATA);
assert(Aon.Results.NumTrials == 21, 'online mode missed the second NewData');
assert(isequaln(Aon.Results, R), 'online results must match the offline hand counts');
assert(evCount('n') == 2, ...
    'obj.Events should have re-broadcast 2 NewData events, saw %d', evCount('n'));
delete(hl);
Aon.disablePlot();
delete(Aon);
fprintf('PASS: online mode follows NewData and re-broadcasts it\n');

fprintf('smoke_test_nafc: ALL PASS\n');
end


function bumpCounter(m)
m('n') = m('n') + 1;
end
