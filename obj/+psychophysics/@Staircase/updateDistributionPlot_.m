function updateDistributionPlot_(obj, plotData)
% updateDistributionPlot_(obj, plotData)
% Redraw the distribution axes: a horizontal histogram of the stimulus
% value at every reversal (or of the sliding threshold estimates, per
% DistributionSource), on the staircase plot's value axis, with the mean
% and median as lines across it and the range as a capped bar at its right.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   plotData — struct from getPlotData_

obj.setupDistributionAxes_();
dax = obj.distAxes_;
if isempty(dax) || ~isvalid(dax)
    return
end

ax = obj.plotAxes_;
if obj.DistributionSource == "SlidingThreshold"
    vals = obj.Results.BlockThreshold(:);
    what = 'no sliding estimates yet';
    label = 'thr ';
    heading = 'Sliding Threshold';
else
    vals = [plotData.revUp.y(:); plotData.revDown.y(:)];
    what = 'no reversals yet';
    label = '';
    heading = 'Reversals';
end
vals = vals(isfinite(vals));

obj.syncDistributionYAxis_();
ylimMain = ylim(ax);

if isempty(vals)
    set(obj.h_distBars_, 'XData', nan(4,1), 'YData', nan(4,1));
    set([obj.h_distRange_ obj.h_distMedian_ obj.h_distMean_], 'XData', nan, 'YData', nan);
    xlabel(dax, 'Count');
    title(dax, sprintf('%s (n=0)', heading));
    subtitle(dax, what);
    return
end

edges = binEdges_(vals, diff(ylimMain));
counts = histcounts(vals, edges);
lo = edges(1:end-1);
hi = edges(2:end);
nBins = numel(counts);

xMax = max(counts);
xRange = xMax * 1.3;
barX = [zeros(1, nBins); counts; counts; zeros(1, nBins)];
barY = [lo; lo; hi; hi];
set(obj.h_distBars_, 'XData', barX, 'YData', barY);

m = mean(vals);
md = median(vals);
xWhisker = xMax * 1.15;
set(obj.h_distMean_,   'XData', [0 xRange], 'YData', [m m]);
set(obj.h_distMedian_, 'XData', [0 xRange], 'YData', [md md]);
set(obj.h_distRange_,  'XData', [xWhisker xWhisker], 'YData', [min(vals) max(vals)]);
xlim(dax, [0 xRange]);

xlabel(dax, 'Count');
title(dax, sprintf('%s (n=%d)', heading, numel(vals)));
subtitle(dax, sprintf('%smean %.2f, median %.2f', label, m, md));
end

function edges = binEdges_(vals, yRange)
% Bin edges centred on the levels a staircase visits. Steps are usually a
% fixed size, so one bar per level is the honest picture; a track too fine
% for that falls back to the toolbox's own binning.
u = unique(vals);
if isscalar(u)
    w = max(yRange/20, eps(max(abs(u), 1)));
    edges = [u - w/2, u + w/2];
    return
end
w = min(diff(u));
nLevels = round((u(end) - u(1))/w) + 1;
if nLevels <= 25
    edges = (u(1) - w/2) + w*(0:nLevels);
else
    [~, edges] = histcounts(vals);
end
end
