function setupDistributionAxes_(obj)
% setupDistributionAxes_(obj)
% Build or tear down the reversal-distribution axes to the right of the
% staircase plot, so that obj.ShowDistribution alone decides whether they exist.
%
% The staircase axes is wrapped in a [1 2] grid that takes over its cell in
% the host layout; the original parent and position are remembered so teardown
% hands the axes back exactly as it was found. The host's layout is never
% edited, which is what keeps this safe inside a paradigm's own GUI.
%
% Parameters:
%   obj — psychophysics.Staircase instance

ax = obj.plotAxes_;
if isempty(ax) || ~isvalid(ax)
    return
end

built = ~isempty(obj.distAxes_) && isvalid(obj.distAxes_);

if ~obj.ShowDistribution
    if built || ~isempty(obj.distHome_)
        obj.teardownDistributionAxes_();
    end
    return
end
if built
    return
end

parent = ax.Parent;
isGrid = isa(parent, 'matlab.ui.container.GridLayout');

obj.distHome_ = struct('Parent', parent, 'IsGrid', isGrid, ...
    'Row', [], 'Column', [], 'Position', []);
if isGrid
    obj.distHome_.Row = ax.Layout.Row;
    obj.distHome_.Column = ax.Layout.Column;
end

if isGrid
    g = uigridlayout(parent, [1 2]);
    g.Padding = [0 0 0 0];
    g.ColumnSpacing = 6;
    g.Layout.Row = obj.distHome_.Row;
    g.Layout.Column = obj.distHome_.Column;
    g.BackgroundColor = parent.BackgroundColor;

    ax.Parent = g;
    ax.Layout.Row = 1;
    ax.Layout.Column = 1;

    % An axes that has had a legend leaves the grid it joins at the size of the
    % cell it came from, and nothing shrinks it. Surplus tracks are zeroed, which
    % does what shrinking would: the axes are not left sharing the cell with them.
    nRows = numel(g.RowHeight);
    nCols = numel(g.ColumnWidth);
    g.RowHeight = [{'1x'}, repmat({0}, 1, nRows - 1)];
    g.ColumnWidth = [{'1x', obj.DISTRIBUTION_WIDTH}, repmat({0}, 1, nCols - 2)];
    g.RowSpacing = 0;

    dax = uiaxes(g);
    dax.Layout.Row = 1;
    dax.Layout.Column = 2;
    obj.distGrid_ = g;
else
    % No layout manager to hand the cell to: split the axes' own rectangle.
    pos = ax.OuterPosition;
    w = min(obj.DISTRIBUTION_WIDTH, pos(3)/2);
    ax.OuterPosition = [pos(1:2), pos(3) - w - 6, pos(4)];
    dax = uiaxes(parent);
    dax.OuterPosition = [pos(1) + pos(3) - w, pos(2), w, pos(4)];
    obj.distHome_.Position = pos;
end
obj.distAxes_ = dax;

inkColor = [0.20 0.22 0.26];
rulerColor = [0.45 0.47 0.52];
dax.FontSize = 11;
dax.Color = [1 1 1];
dax.XColor = rulerColor;
dax.YColor = rulerColor;
dax.LineWidth = 0.75;
dax.TickDir = 'out';
dax.TickLength = [0.005 0.005];
dax.Layer = 'bottom';
dax.GridColor = inkColor;
dax.GridAlpha = 0.10;
dax.MinorGridLineStyle = 'none';
grid(dax, 'on');
box(dax, 'on');
dax.XLabel.String = 'Count';
title(dax, ' ');    % holds the title row open so the two plot areas stay level
dax.XLabel.Color = inkColor;
dax.XLabel.FontSize = dax.FontSize + 1;
dax.Title.Color = inkColor;
dax.Title.FontSize = dax.FontSize + 1;
dax.Title.FontWeight = 'normal';
dax.Subtitle.Color = rulerColor;
dax.Subtitle.FontSize = dax.FontSize - 2;
dax.TitleHorizontalAlignment = 'left';
dax.YTickLabel = {};     % the staircase axes carries the values
disableDefaultInteractivity(dax);

thrColor = hex2rgb(obj.ThresholdColor);
hold(dax, 'on')
obj.h_distBars_ = patch(dax, nan(4,1), nan(4,1), hex2rgb(obj.ReversalColor), ...
    FaceAlpha=0.55, EdgeColor=[1 1 1], LineWidth=0.75);
obj.h_distRange_ = line(dax, nan, nan, 'Color', inkColor, 'LineWidth', 1.5, ...
    'Marker', '_', 'MarkerSize', 9, 'DisplayName', 'Range');
obj.h_distMedian_ = line(dax, nan, nan, 'Color', thrColor, 'LineWidth', 1.5, ...
    'LineStyle', '--', 'DisplayName', 'Median');
obj.h_distMean_ = line(dax, nan, nan, 'Color', thrColor, 'LineWidth', 2, ...
    'LineStyle', '-', 'DisplayName', 'Mean');
hold(dax, 'off')

% Both axes answer to one menu, so the toggle is reachable from either.
if ~isempty(obj.plotContextMenu_) && isvalid(obj.plotContextMenu_)
    dax.ContextMenu = obj.plotContextMenu_;
end

% The two value axes must read as one. linkaxes carries limits only, and
% automatic ticks depend on height, so the staircase axes is copied across
% whenever it finishes rendering (a zoom, a resize, a new limit).
obj.distListener_ = addlistener(ax, 'MarkedClean', @(~,~) obj.syncDistributionYAxis_());
end
