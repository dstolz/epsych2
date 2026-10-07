% smoke_test_staircase_distribution
% psychophysics.Staircase's optional reversal-distribution axes: built beside
% the staircase axes, drawn with the right numbers, handed back intact when
% switched off, and never left behind by a deleted plot. Writes a screenshot
% to tmp/staircase_shots.

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
if exist('epsych_startup','file') == 2
    epsych_startup;
end
outDir = fullfile(repoRoot,'tmp','staircase_shots');
if ~exist(outDir,'dir'), mkdir(outDir); end

rng(7);
HIT  = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS = bitset(uint32(0), uint32(epsych.BitMask.Miss));
DATA = struct('Depth',{},'RespCode',{},'TrialType',{});
depth = -4;
for k = 1:70
    if rand < 1/(1 + exp(-0.55*(depth + 18)))
        DATA(end+1) = struct('Depth',depth,'RespCode',HIT,'TrialType',0); %#ok<SAGROW>
        depth = max(-30, depth - 2);
    else
        DATA(end+1) = struct('Depth',depth,'RespCode',MISS,'TrialType',0); %#ok<SAGROW>
        depth = min(0, depth + 4);
    end
end

ok = true(1,0);

% --- 1. On from the start, in a grid layout ---------------------------------
S = psychophysics.Staircase(DATA, 'Depth');
fig = uifigure('Name','Staircase distribution','Position',[80 80 1100 620]);
prefName = matlab.lang.makeValidName(sprintf('%s_%s', fig.Name, 'Depth'));
gl = uigridlayout(fig,[3 3]);
gl.RowHeight = {'1x', '1x', 30};
ax = uiaxes(gl);
ax.Layout.Row = [1 2]; ax.Layout.Column = [2 3];
S.Plot(ax, ShowDistribution=true);
drawnow

allAx = findobj(fig, 'Type', 'axes');
dax = allAx(allAx ~= ax);
ok(end+1) = report(numel(dax) == 1, 'one extra axes built');
ok(end+1) = report(ax.Parent.Parent == gl && isequal(ax.Parent.Layout.Row, [1 2]) ...
    && isequal(ax.Parent.Layout.Column, [2 3]), 'wrapper grid occupies the original cell');
ok(end+1) = report(isequal(ylim(dax), ylim(ax)), 'value axes match');

vals = S.stimulusValues;
revVals = vals(S.Results.ReversalIdx);
lines = findobj(dax, 'Type', 'line');
names = string(get(lines, 'DisplayName'));
yOf = @(n) get(lines(names == n), "YData");
firstY = @(n) subsref(yOf(n), struct("type","()","subs",{{1}}));
ok(end+1) = report(abs(firstY("Mean") - mean(revVals)) < 1e-9, 'mean line at the mean');
ok(end+1) = report(abs(firstY("Median") - median(revVals)) < 1e-9, 'median line at the median');
ok(end+1) = report(isequal(sort(yOf("Range")), [min(revVals) max(revVals)]), 'range bar spans min..max');
bars = findobj(dax, 'Type', 'patch');
ok(end+1) = report(sum(bars.XData(2,:)) == numel(revVals), 'bar counts total the reversals');

exportapp(fig, fullfile(outDir, 'staircase_distribution.png'));

% --- 2. Off puts the axes back where it was ---------------------------------
S.ShowDistribution = false;
S.refreshPlot();
drawnow
ok(end+1) = report(ax.Parent == gl && isequal(ax.Layout.Row, [1 2]) && isequal(ax.Layout.Column, [2 3]), ...
    'axes returned to its cell');
ok(end+1) = report(numel(findobj(fig,'Type','axes')) == 1, 'distribution axes removed');
ok(end+1) = report(numel(findobj(fig,'Type','uigridlayout')) == 1, 'wrapper grid removed');

% --- 3. On again, repeated updates, and the right-click toggle --------------
S.ShowDistribution = true;
for k = 1:10, S.refreshPlot(); end
drawnow
ok(end+1) = report(numel(findobj(fig,'Type','axes')) == 2, 'one extra axes after 10 updates');

revItem = findall(fig, 'Type', 'uimenu', 'Text', 'Show Reversal Distribution');
thrItem = findall(fig, 'Type', 'uimenu', 'Text', 'Show Sliding Threshold Distribution');
ok(end+1) = report(isscalar(revItem) && isscalar(thrItem), 'two top-level distribution items');
ok(end+1) = report(isempty(findall(fig, 'Type', 'uimenu', 'Text', 'Distribution Of')), 'no submenu');
checks = @() [revItem.Checked == "on", thrItem.Checked == "on"];
nAxes = @() numel(findobj(fig, 'Type', 'axes'));
ok(end+1) = report(isequal(checks(), [true false]), 'reversal item checked, threshold item not');
thrItem.MenuSelectedFcn(thrItem, []);
drawnow
ok(end+1) = report(isequal(checks(), [false true]) && S.DistributionSource == "SlidingThreshold" ...
    && nAxes() == 2, 'choosing the other item switches to it');
thrItem.MenuSelectedFcn(thrItem, []);
drawnow
ok(end+1) = report(isequal(checks(), [false false]) && ~S.ShowDistribution && nAxes() == 1, ...
    'choosing the checked item turns both off');
revItem.MenuSelectedFcn(revItem, []);
drawnow
ok(end+1) = report(isequal(checks(), [true false]) && S.DistributionSource == "Reversals" ...
    && nAxes() == 2, 'and the first brings the reversals back');

% The distribution's value axis is the staircase's: limits, ticks, and
% after a zoom of the staircase axes.
allAx = findobj(fig, 'Type', 'axes');
dax = allAx(allAx ~= ax);
ok(end+1) = report(isequal(dax.YLim, ax.YLim) && isequal(dax.YTick, ax.YTick), 'same limits and ticks');
ylim(ax, [-28 3]);
drawnow; pause(0.2); drawnow
ok(end+1) = report(isequal(dax.YLim, ax.YLim) && isequal(dax.YTick, ax.YTick), 'still the same after a zoom');
ok(end+1) = report(contains(string(dax.Title.String), "Reversals"), 'distribution has a title');

% --- 3b. Sliding threshold line ---------------------------------------------
S.ShowSlidingThreshold = true;
S.refreshPlot();
drawnow
slide = findobj(ax, 'Type', 'line', 'DisplayName', 'Sliding Threshold');
ok(end+1) = report(isscalar(slide) && slide.Visible == "on" && any(isfinite(slide.YData)), ...
    'sliding threshold line drawn');
ok(end+1) = report(slide.YData(end) == S.Results.Threshold, 'it ends on the current threshold');
ok(end+1) = report(slide.XData(end) == numel(DATA), 'and runs to the latest trial');
ok(end+1) = report(numel(S.Results.BlockThreshold) == S.Results.ReversalCount - S.ThresholdFromLastNReversals + 1, ...
    'one estimate per sliding block');
exportapp(fig, fullfile(outDir, 'staircase_distribution_sliding.png'));
S.ShowSlidingThreshold = false;
S.refreshPlot();
ok(end+1) = report(slide.Visible == "off", 'and hides again');

% --- 3c. Distribution of the sliding threshold estimates --------------------
S.DistributionSource = "SlidingThreshold";
S.refreshPlot();
drawnow
dax = findobj(fig, 'Type', 'axes');
dax = dax(dax ~= ax);
bars = findobj(dax, 'Type', 'patch');
bt = S.Results.BlockThreshold;
ok(end+1) = report(sum(bars.XData(2,:)) == nnz(isfinite(bt)), 'bars total the sliding estimates');
lines = findobj(dax, 'Type', 'line');
names = string(get(lines, 'DisplayName'));
ok(end+1) = report(abs(get(lines(names == "Mean"), 'YData') * [1; 0] - mean(bt, 'omitnan')) < 1e-9, ...
    'mean line at the mean of the estimates');
exportapp(fig, fullfile(outDir, 'staircase_distribution_thresholds.png'));
S.DistributionSource = "Reversals";
S.refreshPlot();

% Off and on again inside a grid cell that spans several rows and columns:
% the wrapper must come back one row by two columns, not as large as the cell.
for k = 1:3
    S.ShowDistribution = false; S.refreshPlot();
    S.ShowDistribution = true;  S.refreshPlot();
end
drawnow
wrapper = ax.Parent;
live = @(t) nnz(cellfun(@(x) ~isequal(x, 0), t));
ok(end+1) = report(live(wrapper.RowHeight) == 1 && live(wrapper.ColumnWidth) == 2, ...
    'wrapper keeps one row by two columns of live tracks after repeated off/on');
ok(end+1) = report(ax.Position(4) > 0.9*wrapper.Position(4) && ax.Position(3) > 0.6*wrapper.Position(3), ...
    'plot fills its side of the wrapper after repeated off/on');

% --- 4. Pop-out carries the setting -----------------------------------------
S.popOut();
drawnow
figs = findall(groot, 'Type', 'figure');
pop = figs(arrayfun(@(f) f ~= fig && ~isempty(findobj(f,'Type','axes')), figs));
ok(end+1) = report(~isempty(pop) && numel(findobj(pop(1),'Type','axes')) == 2, ...
    'pop-out window shows the distribution too');
delete(pop(arrayfun(@isvalid, pop)));

% --- 5. No reversals yet, and one level -------------------------------------
S0 = psychophysics.Staircase(DATA(1), 'Depth');
fig0 = uifigure('Position',[80 80 700 400]);
ax0 = uiaxes(uigridlayout(fig0,[1 1]));
S0.Plot(ax0, ShowDistribution=true);
drawnow
ok(end+1) = report(numel(findobj(fig0,'Type','axes')) == 2, 'builds with no reversals');
delete(fig0);

% --- 6. Axes in a plain panel (no grid) -------------------------------------
S5 = psychophysics.Staircase(DATA, 'Depth');
fig5 = uifigure('Position',[80 80 800 450]);
pnl = uipanel(fig5, 'Position', [10 10 780 430]);
ax5 = uiaxes(pnl, 'Position', [10 10 700 380]);
pos0 = ax5.OuterPosition;
S5.Plot(ax5, ShowDistribution=true);
drawnow
ok(end+1) = report(numel(findobj(pnl,'Type','axes')) == 2, 'builds in a non-grid parent');
S5.ShowDistribution = false;
S5.refreshPlot();
ok(end+1) = report(ax5.Parent == pnl && isequal(ax5.OuterPosition, pos0), 'non-grid parent restored');

% --- 7. Deleting the plot's axes or figure leaves nothing running ------------
S5.ShowDistribution = true;
S5.refreshPlot();
delete(fig5);
ok(end+1) = report(true, 'figure deleted with the distribution showing');
delete(fig);
ok(end+1) = report(true, 'main figure deleted');
delete(S);

cleanPref(prefName);
fprintf('SMOKE: %d/%d checks passed\n', nnz(ok), numel(ok));
if ~all(ok), error('smoke_test_staircase_distribution:failed', 'checks failed'); end

function tf = report(cond, msg)
tf = logical(cond);
if tf
    fprintf('SMOKE: ok   %s\n', msg);
else
    fprintf('SMOKE: FAIL %s\n', msg);
end
end

function cleanPref(name)
% The right-click toggles above save the operator's preference; put it back.
if ispref("epsych2_psychophysics_Staircase", name)
    rmpref("epsych2_psychophysics_Staircase", name);
end
end
