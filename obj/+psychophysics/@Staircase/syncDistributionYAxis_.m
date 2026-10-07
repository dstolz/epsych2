function syncDistributionYAxis_(obj)
% syncDistributionYAxis_(obj)
% Make the distribution axes' value axis the staircase axes' own: same limits,
% same ticks, same direction and scale. The two share a row of the layout, so
% what has to match is read from the staircase axes and copied across, not
% recomputed -- automatic ticks depend on the axes' height and on whatever the
% operator has since zoomed to.
%
% Runs after every redraw and whenever the staircase axes finishes rendering.
%
% Parameters:
%   obj — psychophysics.Staircase instance

ax = obj.plotAxes_;
dax = obj.distAxes_;
if isempty(ax) || ~isvalid(ax) || isempty(dax) || ~isvalid(dax)
    return
end

if dax.YScale ~= ax.YScale, dax.YScale = ax.YScale; end
if dax.YDir ~= ax.YDir, dax.YDir = ax.YDir; end
if ~isequal(dax.YLim, ax.YLim), dax.YLim = ax.YLim; end
if ~isequal(dax.YTick, ax.YTick), dax.YTick = ax.YTick; end
if ~isempty(dax.YTickLabel), dax.YTickLabel = {}; end
end
