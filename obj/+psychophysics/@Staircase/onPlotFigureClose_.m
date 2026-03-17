function onPlotFigureClose_(obj, fig)
% onPlotFigureClose_(obj, fig)
% CloseRequestFcn handler for an owned plot figure.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   fig — matlab.ui.Figure that owns the axes

if isempty(fig) || ~isvalid(fig)
    return
end
obj.disablePlot();
