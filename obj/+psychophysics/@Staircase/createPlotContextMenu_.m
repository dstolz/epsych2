function createPlotContextMenu_(obj)
% createPlotContextMenu_(obj)
% Build a right-click context menu on the plot axes for adjusting
% ThresholdFromLastNReversals, ThresholdFormula, ShowSteps, and ShowReversals.
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

% --- Show Steps toggle ---
uimenu(cm, 'Text', 'Show Steps', 'Separator', 'on', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ShowSteps), ...
    'MenuSelectedFcn', @(src,~) toggleShowSteps(obj, src));

% --- Show Reversals toggle ---
uimenu(cm, 'Text', 'Show Reversals', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ShowReversals), ...
    'MenuSelectedFcn', @(src,~) toggleShowReversals(obj, src));

obj.plotAxes_.ContextMenu = cm;
obj.plotContextMenu_ = cm;
end

%% --- Local helper functions ---

function setReversalCount(obj, parentMenu, n)
    obj.ThresholdFromLastNReversals = n;
    obj.recompute_history();
    obj.updatePlot_();
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
    obj.recompute_history();
    obj.updatePlot_();
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
    obj.recompute_history();
    obj.updatePlot_();
    formulaMap = struct('Mean', 'Mean', 'GeometricMean', 'Geometric Mean');
    activeText = formulaMap.(char(formula));
    for k = 1:numel(parentMenu.Children)
        parentMenu.Children(k).Checked = matlab.lang.OnOffSwitchState( ...
            strcmp(parentMenu.Children(k).Text, activeText));
    end
end

function toggleShowSteps(obj, src)
    obj.ShowSteps = ~obj.ShowSteps;
    src.Checked = matlab.lang.OnOffSwitchState(obj.ShowSteps);
    obj.updatePlot_();
end

function toggleShowReversals(obj, src)
    obj.ShowReversals = ~obj.ShowReversals;
    src.Checked = matlab.lang.OnOffSwitchState(obj.ShowReversals);
    obj.updatePlot_();
end
