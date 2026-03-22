function updatePlot_(obj)
% updatePlot_(obj)
% Update staircase history plot graphics from current staircase state.
%
% Parameters:
%   obj — psychophysics.Staircase instance

vprintf(4, 'Updating psychophysics.Staircase plot')

if isempty(obj.plotAxes_) || ~isvalid(obj.plotAxes_)
    return
end

if isempty(obj.h_line) || ~isvalid(obj.h_line)
    obj.setupPlotAxes_();
end

if isempty(obj.h_line) || ~isvalid(obj.h_line)
    return
end

[x, y, c, xCatch, yCatch, cCatch, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = obj.getPlotData_();

set(obj.h_line, 'XData', x, 'YData', y);
set(obj.h_points, 'XData', x, 'YData', y, ...
    'SizeData', obj.MarkerSize, 'CData', hex2rgb(c));
set(obj.CatchH, 'XData', xCatch, 'YData', yCatch, ...
    'SizeData', obj.MarkerSize, 'CData', hex2rgb(cCatch));

if obj.ShowSteps
    set(obj.StepH, 'Visible', 'on', 'XData', xStep, 'YData', yStep, ...
        'SizeData', obj.StepMarkerSize, 'CData', hex2rgb(cStep));
else
    set(obj.StepH, 'Visible', 'off', 'XData', nan, 'YData', nan);
end

if obj.ShowReversals
    set(obj.ReversalUpH, 'Visible', 'on', 'XData', xRevUp, 'YData', yRevUp, ...
        'SizeData', obj.ReversalMarkerSize);
    set(obj.ReversalDownH, 'Visible', 'on', 'XData', xRevDown, 'YData', yRevDown, ...
        'SizeData', obj.ReversalMarkerSize);
else
    set(obj.ReversalUpH, 'Visible', 'off', 'XData', nan, 'YData', nan);
    set(obj.ReversalDownH, 'Visible', 'off', 'XData', nan, 'YData', nan);
end

obj.updateThresholdOverlay_();
axis(obj.plotAxes_,'normal')
obj.updatePlotLabels_();
