function updateLegend_(obj, plotData)
% updateLegend_(obj, plotData)
% Rebuild the legend so it names only what is currently drawn: the visible
% series plus a color swatch for each response outcome present in the data.
%
% The legend is rebuilt only when its contents change, since it is otherwise
% recreated on every trial of a running session.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   plotData — struct from getPlotData_

ax = obj.plotAxes_;
if isempty(ax) || ~isvalid(ax)
    return
end

% The trace and the plain stimulus marker are self-evident and are left out:
% legend rows cost plot height, which is scarce in an embedded axes.
items = {};

if hasData(plotData.catch)
    items{end+1} = obj.CatchH;
end

if obj.ShowSteps && hasData(plotData.step)
    items{end+1} = obj.StepH;
end

% Up and down reversals share one entry: the pair of triangles reads as a
% single annotation, and two entries doubled the legend for no information.
if obj.ShowReversals && (hasData(plotData.revUp) || hasData(plotData.revDown))
    if hasData(plotData.revUp)
        items{end+1} = obj.ReversalUpH;
    else
        items{end+1} = obj.ReversalDownH;
    end
    items{end}.DisplayName = 'Reversal';
end

if ~isempty(obj.Results.Threshold) && any(isfinite(obj.h_thrline.YData))
    items{end+1} = obj.h_thrline;
end

for idx = find(plotData.bitsPresent)
    if idx <= numel(obj.bitSwatchH_) && isvalid(obj.bitSwatchH_(idx))
        items{end+1} = obj.bitSwatchH_(idx);
    end
end

% Nothing plotted yet: an empty legend is worse than none at all.
if isempty(items)
    if ~isempty(obj.legendH_) && isvalid(obj.legendH_)
        delete(obj.legendH_)
    end
    obj.legendKey_ = "";
    return
end

% Names are collected separately: concatenating lines, patches, and scatters
% yields a heterogeneous array that does not support dot access.
names = cellfun(@(h) string(h.DisplayName), items);
entries = [items{:}];

% Wrap to two rows once there are more than five entries: a single long row
% is clipped in a narrow axes, and inside the axes it would stretch across
% the trials it describes. Column count comes from the entry count rather
% than the axes width, which a web figure has not resolved on the first draw.
nColumns = numel(entries);
if nColumns > 5
    nColumns = ceil(nColumns / 2);
end

key = strjoin(names, "|");
if key == obj.legendKey_ && ~isempty(obj.legendH_) && isvalid(obj.legendH_)
    return
end

if ~isempty(obj.legendH_) && isvalid(obj.legendH_)
    delete(obj.legendH_)
end

% Properties are set after construction because legend() reads trailing
% arguments as entry labels. Orientation comes before NumColumns: setting
% it to horizontal resets the column count to one row of every entry.
lgd = legend(ax, entries);
lgd.Location = 'southwest';
lgd.Orientation = 'horizontal';
lgd.NumColumns = nColumns;
% Opaque inside the axes: transparent text sat on top of the trace.
lgd.Box = 'on';
lgd.Color = [1 1 1];
lgd.EdgeColor = [0.80 0.81 0.84];
lgd.FontSize = 9;
lgd.TextColor = [0.20 0.22 0.26];
lgd.ItemTokenSize = [12 10];
lgd.AutoUpdate = 'off';

obj.legendH_ = lgd;
obj.legendKey_ = key;
end

function tf = hasData(series)
% True when a plotted series holds at least one finite point.
tf = any(isfinite(series.x)) && any(isfinite(series.y));
end
