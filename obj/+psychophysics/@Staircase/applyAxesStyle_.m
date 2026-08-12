function applyAxesStyle_(obj)
% applyAxesStyle_(obj)
% Apply the staircase plot's visual style to the axes chrome: a recessive
% grid and rulers so the trial markers, which carry the data, dominate.
%
% Parameters:
%   obj — psychophysics.Staircase instance

ax = obj.plotAxes_;
if isempty(ax) || ~isvalid(ax)
    return
end

inkColor = [0.20 0.22 0.26];
rulerColor = [0.45 0.47 0.52];

ax.FontSize = 11;
ax.Color = [1 1 1];
ax.XColor = rulerColor;
ax.YColor = rulerColor;
ax.LineWidth = 0.75;
ax.TickDir = 'out';
ax.TickLength = [0.005 0.005];

% Grid sits under the data and reads as a hint, not as a series.
ax.Layer = 'bottom';
ax.GridColor = inkColor;
ax.GridAlpha = 0.10;
ax.GridLineStyle = '-';
ax.MinorGridLineStyle = 'none';
grid(ax, 'on');
box(ax, 'on');

ax.XLabel.Color = inkColor;
ax.YLabel.Color = inkColor;
ax.XLabel.FontSize = ax.FontSize + 1;
ax.YLabel.FontSize = ax.FontSize + 1;

ax.Title.Color = inkColor;
ax.Title.FontSize = ax.FontSize + 1;
ax.Title.FontWeight = 'normal';
ax.Subtitle.Color = rulerColor;
ax.Subtitle.FontSize = ax.FontSize - 1;
ax.TitleHorizontalAlignment = 'left';

% The owned figure is ours to style; an embedded axes keeps its host's look.
if obj.plotOwnsFigure_ && ~isempty(obj.plotFigure_) && isvalid(obj.plotFigure_)
    obj.plotFigure_.Color = [1 1 1];
end
