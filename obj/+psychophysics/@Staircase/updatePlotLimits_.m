function updatePlotLimits_(obj, plotData)
% updatePlotLimits_(obj, plotData)
% Set axis limits with margins around the plotted data.
%
% MATLAB's automatic limits leave trials sitting on the axes rulers, where a
% marker is clipped in half and the first and last trials are hard to read.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   plotData — struct from getPlotData_

ax = obj.plotAxes_;
if isempty(ax) || ~isvalid(ax)
    return
end

x = collect(plotData.main.x, plotData.catch.x);
y = collect(plotData.main.y, plotData.catch.y, ...
    obj.h_thrreg.YData(:), obj.h_thrline.YData(:));

if isempty(x) || isempty(y)
    axis(ax, 'normal')
    return
end

xlim(ax, padded(x, 0.02, 0.5));
ylim(ax, padded(y, 0.08, 1));
end

function v = collect(varargin)
% Concatenate finite values from the supplied vectors.
v = vertcat(varargin{:});
v = v(isfinite(v));
end

function lim = padded(v, fraction, minPad)
% Symmetric margin proportional to the data range, with a floor for the
% degenerate case of a single distinct value.
lo = min(v);
hi = max(v);
pad = max(fraction*(hi - lo), minPad);
lim = [lo - pad, hi + pad];
end
