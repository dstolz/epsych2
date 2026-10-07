function createPlotContextMenu_(obj)
% createPlotContextMenu_(obj)
% Build a right-click context menu on the plot axes for adjusting
% ThresholdFromLastNReversals, ThresholdFormula, ApplyWeightedCorrection,
% ShowSteps, ShowReversals, the sliding threshold and the distribution axes,
% and for opening the plot in a window of its own.
%
% Parameters:
%   obj — psychophysics.Staircase instance

if isempty(obj.plotAxes_) || ~isvalid(obj.plotAxes_) ...
        || isempty(obj.plotFigure_) || ~isvalid(obj.plotFigure_)
    return
end

cm = uicontextmenu(obj.plotFigure_);

% --- Threshold Reversals submenu ---
mRev = uimenu(cm, 'Text', 'Threshold Reversals');
presets = [2 4 6 8 10 12];
for k = 1:numel(presets)
    n = presets(k);
    uimenu(mRev, 'Text', sprintf('%d', n), ...
        'Checked', matlab.lang.OnOffSwitchState(n == obj.ThresholdFromLastNReversals), ...
        'MenuSelectedFcn', @(src,~) setReversalCount(obj, mRev, n));
end
uimenu(mRev, 'Text', 'Custom...', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) customReversalCount(obj, mRev));

% --- Threshold Formula submenu ---
mFormula = uimenu(cm, 'Text', 'Threshold Formula');
uimenu(mFormula, 'Text', 'Mean', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ThresholdFormula == "Mean"), ...
    'MenuSelectedFcn', @(src,~) setFormula(obj, mFormula, "Mean"));
uimenu(mFormula, 'Text', 'Geometric Mean', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ThresholdFormula == "GeometricMean"), ...
    'MenuSelectedFcn', @(src,~) setFormula(obj, mFormula, "GeometricMean"));

% --- Weighted-staircase correction (Hoover 2025) ---
% An analysis setting, not a display one: it changes Results.Threshold and
% the sliding-block estimates, so every threshold the plot shows moves with it.
uimenu(cm, 'Text', 'Apply Weighted Correction', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ApplyWeightedCorrection), ...
    'MenuSelectedFcn', @(src,~) toggleWeightedCorrection(obj, src));

% --- Show Steps toggle ---
uimenu(cm, 'Text', 'Show Steps', 'Separator', 'on', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ShowSteps), ...
    'MenuSelectedFcn', @(src,~) toggleShowSteps(obj, src));

% --- Show Reversals toggle ---
uimenu(cm, 'Text', 'Show Reversals', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ShowReversals), ...
    'MenuSelectedFcn', @(src,~) toggleShowReversals(obj, src));

% --- Sliding threshold toggle ---
uimenu(cm, 'Text', 'Show Sliding Threshold', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ShowSlidingThreshold), ...
    'MenuSelectedFcn', @(src,~) toggleShowSlidingThreshold(obj, src));

% --- Distribution axes: one item per source, mutually exclusive, both
% unchecked meaning no distribution axes. They share the pair of properties
% ShowDistribution and DistributionSource, so the checks are derived from them.
mDistRev = uimenu(cm, 'Text', 'Show Reversal Distribution');
mDistThr = uimenu(cm, 'Text', 'Show Sliding Threshold Distribution');
mDistRev.MenuSelectedFcn = @(~,~) selectDistribution(obj, mDistRev, mDistThr, "Reversals");
mDistThr.MenuSelectedFcn = @(~,~) selectDistribution(obj, mDistRev, mDistThr, "SlidingThreshold");
checkDistributionItems(obj, mDistRev, mDistThr);

% --- Pop-out window (gui.PopOut) ---
obj.addPopOutMenu_(cm);

obj.plotAxes_.ContextMenu = cm;
obj.plotContextMenu_ = cm;
end

%% --- Local helper functions ---
% The analysis setters recompute and redraw; these helpers only record the
% choice and keep the check marks honest.

function setReversalCount(obj, parentMenu, n)
    obj.ThresholdFromLastNReversals = n;
    obj.saveMenuPreferences_();
    updateReversalChecks(parentMenu, n);
end

function customReversalCount(obj, parentMenu)
    answer = inputdlg('Number of reversals for threshold:', ...
        'Threshold Reversals', [1 35], {num2str(obj.ThresholdFromLastNReversals)});
    if isempty(answer)
        return
    end
    n = round(str2double(answer{1}));
    if isnan(n) || n < 1
        return
    end
    obj.ThresholdFromLastNReversals = n;
    obj.saveMenuPreferences_();
    updateReversalChecks(parentMenu, n);
end

function updateReversalChecks(parentMenu, activeN)
    children = parentMenu.Children;
    for k = 1:numel(children)
        txt = children(k).Text;
        val = str2double(txt);
        if ~isnan(val)
            children(k).Checked = matlab.lang.OnOffSwitchState(val == activeN);
        end
    end
end

function setFormula(obj, parentMenu, formula)
    obj.ThresholdFormula = formula;
    obj.saveMenuPreferences_();
    formulaMap = struct('Mean', 'Mean', 'GeometricMean', 'Geometric Mean');
    activeText = formulaMap.(char(formula));
    for k = 1:numel(parentMenu.Children)
        parentMenu.Children(k).Checked = matlab.lang.OnOffSwitchState( ...
            strcmp(parentMenu.Children(k).Text, activeText));
    end
end

function toggleWeightedCorrection(obj, src)
    obj.ApplyWeightedCorrection = ~obj.ApplyWeightedCorrection;
    src.Checked = matlab.lang.OnOffSwitchState(obj.ApplyWeightedCorrection);
    obj.saveMenuPreferences_();
end

function toggleShowSteps(obj, src)
    obj.ShowSteps = ~obj.ShowSteps;
    src.Checked = matlab.lang.OnOffSwitchState(obj.ShowSteps);
    obj.updatePlot_();
    obj.saveMenuPreferences_();
end

function toggleShowSlidingThreshold(obj, src)
    obj.ShowSlidingThreshold = ~obj.ShowSlidingThreshold;
    src.Checked = matlab.lang.OnOffSwitchState(obj.ShowSlidingThreshold);
    obj.updatePlot_();
    obj.saveMenuPreferences_();
end

function selectDistribution(obj, mRev, mThr, source)
    % Choosing the source already showing turns the distribution off; the
    % other one switches to it.
    if obj.ShowDistribution && obj.DistributionSource == source
        obj.ShowDistribution = false;
    else
        obj.DistributionSource = source;
        obj.ShowDistribution = true;
    end
    checkDistributionItems(obj, mRev, mThr);
    obj.updatePlot_();
    obj.saveMenuPreferences_();
end

function checkDistributionItems(obj, mRev, mThr)
    mRev.Checked = matlab.lang.OnOffSwitchState( ...
        obj.ShowDistribution && obj.DistributionSource == "Reversals");
    mThr.Checked = matlab.lang.OnOffSwitchState( ...
        obj.ShowDistribution && obj.DistributionSource == "SlidingThreshold");
end

function toggleShowReversals(obj, src)
    obj.ShowReversals = ~obj.ShowReversals;
    src.Checked = matlab.lang.OnOffSwitchState(obj.ShowReversals);
    obj.updatePlot_();
    obj.saveMenuPreferences_();
end
