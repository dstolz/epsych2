function updatePlot_(obj)
% updatePlot_(obj)
% Update staircase history plot graphics from current staircase state.
%
% Parameters:
%   obj — psychophysics.Staircase instance

% No per-update vprintf: the log takes every level by default, so a trace
% record here was a dbstack and a file write on every trial.

if isempty(obj.plotAxes_) || ~isvalid(obj.plotAxes_)
    return
end

if isempty(obj.h_line) || ~isvalid(obj.h_line)
    obj.setupPlotAxes_();
end

if isempty(obj.h_line) || ~isvalid(obj.h_line)
    return
end


p = obj.getPlotData_();


set(obj.h_line, 'XData', p.main.x, 'YData', p.main.y);
set(obj.h_points, 'XData', p.main.x, 'YData', p.main.y, ...
    'SizeData', obj.MarkerSize, 'CData', localRgb(p.main.c));
set(obj.CatchH, 'XData', p.catch.x, 'YData', p.catch.y, ...
    'SizeData', obj.MarkerSize, 'CData', localRgb(p.catch.c));


if obj.ShowSteps
    set(obj.StepH, 'Visible', 'on', 'XData', p.step.x, 'YData', p.step.y, ...
        'SizeData', obj.StepMarkerSize, 'CData', localRgb(p.step.c));
else
    set(obj.StepH, 'Visible', 'off', 'XData', nan, 'YData', nan, ...
        'CData', hex2rgb(obj.NeutralColor));
end


if obj.ShowReversals
    set(obj.ReversalUpH, 'Visible', 'on', 'XData', p.revUp.x, 'YData', p.revUp.y, ...
        'SizeData', obj.ReversalMarkerSize);
    set(obj.ReversalDownH, 'Visible', 'on', 'XData', p.revDown.x, 'YData', p.revDown.y, ...
        'SizeData', obj.ReversalMarkerSize);
else
    set(obj.ReversalUpH, 'Visible', 'off', 'XData', nan, 'YData', nan);
    set(obj.ReversalDownH, 'Visible', 'off', 'XData', nan, 'YData', nan);
end

obj.updateThresholdOverlay_();
obj.updateSlidingThreshold_();
obj.updatePlotLimits_(p);
obj.updateDistributionPlot_(p);
obj.updatePlotLabels_();
obj.updateLegend_(p);
end


function rgb = localRgb(hexColors)
% rgb = localRgb(hexColors)
% One RGB row per hex colour, converting each DISTINCT colour once.
%
% hex2rgb validates its input a string at a time, and the points of a
% track share a handful of colours: converting all of them on every trial
% was half of what a redraw cost at a thousand trials (16 of 32 ms,
% profiled), and grew with the session.
if isempty(hexColors)
    rgb = hex2rgb(hexColors);
    return
end
[u, ~, idx] = unique(string(hexColors(:)));
rgbU = hex2rgb(u);
rgb = rgbU(idx, :);
end
