function updatePlot_(obj)
% updatePlot_(obj)
% Redraw the plot from current Results. The three plot types share nothing
% but the axes, so each update clears and redraws rather than bookkeeping
% handles across types; the per-trial data volume makes that cheap.
%
% Parameters:
%   obj — psychophysics.NAFC instance

if ~obj.plotEnabled_ || isempty(obj.plotAxes_) || ~isvalid(obj.plotAxes_)
    return
end

ax = obj.plotAxes_;
R = obj.Results;

cla(ax);                 % keeps the axes ContextMenu and style
% cla spares HandleVisibility='off' graphics, and the connecting curves and
% the chance line are deliberately hidden so they cost no legend row. Without
% this every refresh would leave its curves behind: an online session ends up
% drawing the whole history of the plot on top of itself.
delete(allchild(ax));
legend(ax, 'off');
colorbar(ax, 'off');

% Undo what a previous confusion draw may have left behind.
ax.YDir = 'normal';
ax.XTickMode = 'auto';
ax.YTickMode = 'auto';
ax.XTickLabelMode = 'auto';
ax.YTickLabelMode = 'auto';

hold(ax, 'on');
switch obj.PlotType
    case "choice"
        obj.drawChoicePlot_(ax, R);
    case "performance"
        obj.drawPerformancePlot_(ax, R);
    case "confusion"
        obj.drawConfusionPlot_(ax, R);
end
hold(ax, 'off');

if obj.plotOwnsFigure_ && ~isempty(obj.plotFigure_) && isvalid(obj.plotFigure_)
    obj.plotFigure_.Name = obj.plotWindowTitle_();
end
