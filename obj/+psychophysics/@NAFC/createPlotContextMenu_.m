function createPlotContextMenu_(obj)
% createPlotContextMenu_(obj)
% Build a right-click context menu on the plot axes for switching PlotType,
% toggling the chance-level reference, and opening the plot in a window of
% its own (gui.PopOut).
%
% Parameters:
%   obj — psychophysics.NAFC instance

if isempty(obj.plotAxes_) || ~isvalid(obj.plotAxes_) ...
        || isempty(obj.plotFigure_) || ~isvalid(obj.plotFigure_)
    return
end

cm = uicontextmenu(obj.plotFigure_);

% --- Plot Type submenu ---
types = ["choice", "performance", "confusion"];
names = ["Choice Functions", "Proportion Correct", "Confusion Matrix"];
mType = uimenu(cm, 'Text', 'Plot Type');
for k = 1:numel(types)
    uimenu(mType, 'Text', names(k), ...
        'Checked', matlab.lang.OnOffSwitchState(obj.PlotType == types(k)), ...
        'MenuSelectedFcn', @(~,~) setPlotType(obj, mType, types(k), names(k)));
end

% --- Chance-level toggle (curve plots only; the heatmap ignores it) ---
uimenu(cm, 'Text', 'Show Chance Level', 'Separator', 'on', ...
    'Checked', matlab.lang.OnOffSwitchState(obj.ShowChance), ...
    'MenuSelectedFcn', @(src,~) toggleChance(obj, src));

% --- Pop-out window (gui.PopOut) ---
obj.addPopOutMenu_(cm);

obj.plotAxes_.ContextMenu = cm;
obj.plotContextMenu_ = cm;
end

%% --- Local helper functions ---

function setPlotType(obj, parentMenu, type, name)
    % The PlotType setter redraws a live plot on its own.
    obj.PlotType = type;
    for k = 1:numel(parentMenu.Children)
        parentMenu.Children(k).Checked = matlab.lang.OnOffSwitchState( ...
            strcmp(parentMenu.Children(k).Text, name));
    end
end

function toggleChance(obj, src)
    obj.ShowChance = ~obj.ShowChance;
    src.Checked = matlab.lang.OnOffSwitchState(obj.ShowChance);
    obj.refreshPlot();
end
