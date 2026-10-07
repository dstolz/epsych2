% smoke_test_staircase_weighted_toggle
% psychophysics.Staircase's right-click "Apply Weighted Correction": the
% toggle routes the corrected threshold into every threshold estimate the
% plot shows -- title, threshold line, sliding-block thresholds and their
% summaries, the sliding-threshold distribution -- remembers the choice, and
% puts everything back when switched off. Writes a screenshot to
% tmp/staircase_shots.

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
if exist('epsych_startup','file') == 2
    epsych_startup;
end
outDir = fullfile(repoRoot,'tmp','staircase_shots');
if ~exist(outDir,'dir'), mkdir(outDir); end

% A weighted track: -2 after a hit, +4 after a miss (psi = 2/3).
rng(7);
HIT  = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS = bitset(uint32(0), uint32(epsych.BitMask.Miss));
DATA = struct('Depth',{},'RespCode',{},'TrialType',{});
depth = -4;
for k = 1:90
    if rand < 1/(1 + exp(-0.55*(depth + 18)))
        DATA(end+1) = struct('Depth',depth,'RespCode',HIT,'TrialType',0); %#ok<SAGROW>
        depth = max(-30, depth - 2);
    else
        DATA(end+1) = struct('Depth',depth,'RespCode',MISS,'TrialType',0); %#ok<SAGROW>
        depth = min(0, depth + 4);
    end
end

ok = true(1,0);
figName = 'Staircase weighted toggle smoke';
prefName = matlab.lang.makeValidName(sprintf('%s_%s', figName, 'Depth'));
cleanPref(prefName);

% --- 1. Uncorrected baseline -------------------------------------------------
S = psychophysics.Staircase(DATA, 'Depth');
fig = uifigure('Name', figName, 'Position', [80 80 1100 560]);
ax = uiaxes(uigridlayout(fig, [1 1]));
S.Plot(ax, ShowSlidingThreshold=true, ShowDistribution=true, DistributionSource="SlidingThreshold");
drawnow
legacy = S.Results;
thr = findobj(ax, 'Type', 'line', 'DisplayName', 'Threshold');
ok(end+1) = report(~S.ApplyWeightedCorrection && isempty(legacy.Weighted), 'off by default');
ok(end+1) = report(contains(string(ax.Title.String), "| Threshold ("), 'title names the plain threshold');
ok(end+1) = report(isscalar(thr) && thr.LineStyle == "-", 'threshold line solid');
ok(end+1) = report(numel(legacy.BlockThreshold) > 3, 'session has several sliding blocks');

% --- 2. Toggle on from the menu ------------------------------------------------
item = findobj(ax.ContextMenu, 'Text', 'Apply Weighted Correction');
ok(end+1) = report(isscalar(item) && item.Checked == "off", 'menu item present, unchecked');
item.MenuSelectedFcn(item, []);
drawnow
R = S.Results;
W = S.weightedThreshold();
ok(end+1) = report(S.ApplyWeightedCorrection && item.Checked == "on", 'menu turns it on');
ok(end+1) = report(W.Valid && R.Threshold == W.Threshold && R.Threshold ~= legacy.Threshold, ...
    'Results.Threshold is the corrected threshold');
ok(end+1) = report(abs(W.Correction - (-0.5)) < 1e-9, sprintf('correction -(-2+4)/4 = %g', W.Correction));
ok(end+1) = report(contains(string(ax.Title.String), "| Corrected threshold (") ...
    && contains(string(ax.Title.String), "min "), 'title names the corrected threshold and block summary');
thr = findobj(ax, 'Type', 'line', 'DisplayName', 'Corrected Threshold');
ok(end+1) = report(isscalar(thr) && thr.LineStyle == "--" && thr.YData(1) == R.Threshold, ...
    'threshold line dashed, named, at the corrected value');
ok(end+1) = report(any(string(ax.Legend.String) == "Corrected Threshold") ...
    && any(string(ax.Legend.String) == "Corrected Sliding Threshold"), 'legend names both corrected lines');

% --- 3. Sliding blocks are corrected, block by block ---------------------------
n = S.ThresholdFromLastNReversals;
nb = numel(R.BlockThreshold);
blockOk = nb == numel(legacy.BlockThreshold);
for k = 1:nb
    Wk = S.weightedThreshold(NumReversals=n, LastReversal=k+n-1);
    blockOk = blockOk && isequaln(R.BlockThreshold(k), Wk.Threshold);
end
ok(end+1) = report(blockOk, 'each block is weightedThreshold over its own reversals');
ok(end+1) = report(R.BlockThreshold(end) == R.Threshold, 'latest block is the threshold');
% N is even, so every block is already balanced and the steps never change:
% each corrected block is its plain block plus the one correction.
ok(end+1) = report(max(abs(R.BlockThreshold - legacy.BlockThreshold - W.Correction)) < 1e-9, ...
    'constant-step track: blocks shift by exactly the correction');
ok(end+1) = report(R.MinBlockThreshold == min(R.BlockThreshold) && R.MaxBlockThreshold == max(R.BlockThreshold) ...
    && R.MedianBlockThreshold == median(R.BlockThreshold), 'block summaries from corrected blocks');
slide = findobj(ax, 'Type', 'line', 'DisplayName', 'Corrected Sliding Threshold');
ok(end+1) = report(isscalar(slide) && all(ismember(slide.YData, R.BlockThreshold)), 'sliding line draws corrected blocks');
dax = findobj(fig, 'Type', 'axes');
dax = dax(dax ~= ax);
ok(end+1) = report(isscalar(dax) && startsWith(string(dax.Title.String), "Corrected Sliding Thr."), ...
    'distribution heading says corrected');
exportapp(fig, fullfile(outDir, 'staircase_weighted_toggle.png'));

% --- 4. Remembered, and restored by the next plot in the same window -----------
ok(end+1) = report(ispref('epsych2_psychophysics_Staircase', prefName) ...
    && getpref('epsych2_psychophysics_Staircase', prefName).ApplyWeightedCorrection, 'choice saved');
S2 = psychophysics.Staircase(DATA, 'Depth');
S2.Plot(ax);
drawnow
ok(end+1) = report(S2.ApplyWeightedCorrection && ~isempty(S2.Results.Weighted) ...
    && S2.Results.Threshold == R.Threshold, 'restored and recomputed on Plot');
delete(S2);
S.Plot(ax);
drawnow

% --- 5. Pop-out carries it ------------------------------------------------------
before = findall(groot, 'Type', 'figure');
S.popOut();
drawnow
figs = findall(groot, 'Type', 'figure');
pop = setdiff(figs, before);
popAx = findobj(pop, 'Type', 'axes');
ok(end+1) = report(~isempty(popAx) && any(contains(string(arrayfun(@(a) string(a.Title.String), popAx)), "Corrected threshold (")), ...
    'pop-out shows the corrected threshold');
delete(pop(isvalid(pop)));

% --- 6. Refused correction says so --------------------------------------------
S.WeightedStepAfterYes = 2;     % same sign as the step after a no: refused
S.WeightedStepAfterNo  = 4;
S.refresh_history();
drawnow
ok(end+1) = report(isnan(S.Results.Threshold) && all(isnan(S.Results.BlockThreshold)), 'refusal: no thresholds');
ok(end+1) = report(contains(string(ax.Title.String), "Corrected threshold: unavailable"), 'title says unavailable');
S.WeightedStepAfterYes = NaN;
S.WeightedStepAfterNo  = NaN;

% --- 7. Toggle off restores the plain estimates --------------------------------
item = findobj(ax.ContextMenu, 'Text', 'Apply Weighted Correction');
item.MenuSelectedFcn(item, []);
drawnow
R = S.Results;
thr = findobj(ax, 'Type', 'line', 'DisplayName', 'Threshold');
ok(end+1) = report(~S.ApplyWeightedCorrection && isempty(R.Weighted) && R.Threshold == legacy.Threshold ...
    && isequaln(R.BlockThreshold, legacy.BlockThreshold), 'off: plain results back');
ok(end+1) = report(isscalar(thr) && thr.LineStyle == "-" && contains(string(ax.Title.String), "| Threshold ("), ...
    'off: solid line, plain title');

% --- 8. Flag set without a refresh does not break a redraw ----------------------
S.ApplyWeightedCorrection = true;
try
    S.refreshPlot();
    drawnow
    stale = true;
catch ME
    fprintf('%s\n', ME.message);
    stale = false;
end
ok(end+1) = report(stale && contains(string(ax.Title.String), "| Threshold ("), ...
    'stale flag: plot shows what Results holds');

% --- 9. The block memo never changes an answer ----------------------------------
% One object fed the session trial by trial (as NewData does), then seeking
% backward, then an edit mid-session, then a step setting changed -- each
% compared with a fresh object that has no memo.
addpath(fullfile(repoRoot, 'tmp'));   % FakeScatterRuntime
Rg = FakeScatterRuntime();
Sg = psychophysics.Staircase(Rg, struct('validName','Depth'));
Sg.ApplyWeightedCorrection = true;
feed = @(D) Rg.EVENTS.notify('NewData', epsych.TrialsData( ...
    struct('DATA', {D}, 'Subject', 'FakeSubject', 'BoxID', 1)));
same = true;
for k = 1:numel(DATA)
    feed(DATA(1:k));
    same = same && sameBlocks(Sg, DATA(1:k), {});
end
ok(end+1) = report(same && numel(Sg.Results.BlockThreshold) > 3, 'growing session: memo equals fresh at every trial');
feed(DATA(1:55));
ok(end+1) = report(sameBlocks(Sg, DATA(1:55), {}), 'seek backward: memo equals fresh');
D2 = DATA; D2(20).Depth = D2(20).Depth - 6;
feed(D2);
ok(end+1) = report(sameBlocks(Sg, D2, {}), 'edit mid-session: memo equals fresh');
Sg.WeightedStepAfterNo = 6; Sg.refresh_history();
ok(end+1) = report(sameBlocks(Sg, D2, {'WeightedStepAfterNo', 6}), 'setting changed: memo equals fresh');
delete(Sg);

% --- 10. Cost of the per-block correction ---------------------------------------
S.refresh_history();
tic; S.refresh_history(); t = toc;
fprintf('SMOKE: info refresh with correction, %d trials, %d blocks: %.1f ms\n', ...
    numel(DATA), numel(S.Results.BlockThreshold), 1000*t);

delete(fig);
delete(S);
cleanPref(prefName);
fprintf('SMOKE: %d/%d checks passed\n', nnz(ok), numel(ok));
if ~all(ok), error('smoke_test_staircase_weighted_toggle:failed', 'checks failed'); end

function tf = report(cond, msg)
tf = logical(cond);
if tf
    fprintf('SMOKE: ok   %s\n', msg);
else
    fprintf('SMOKE: FAIL %s\n', msg);
end
end

function tf = sameBlocks(S, D, props)
F = psychophysics.Staircase(D, 'Depth');
for i = 1:2:numel(props)
    F.(props{i}) = props{i+1};
end
F.ApplyWeightedCorrection = true;
F.refresh_history();
tf = isequaln(S.Results.BlockThreshold, F.Results.BlockThreshold) ...
    && isequaln(S.Results.Threshold, F.Results.Threshold);
delete(F);
end

function cleanPref(name)
if ispref("epsych2_psychophysics_Staircase", name)
    rmpref("epsych2_psychophysics_Staircase", name);
end
end
