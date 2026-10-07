function teardownDistributionAxes_(obj)
% teardownDistributionAxes_(obj)
% Remove the reversal-distribution axes and give the staircase axes back its
% original parent and position.
%
% An axes already being destroyed is left where it is: this runs from the
% ObjectBeingDestroyed listener too, when reparenting would fight the deletion.
%
% Parameters:
%   obj — psychophysics.Staircase instance

ax = obj.plotAxes_;
home = obj.distHome_;

if ~isempty(obj.distListener_) && isvalid(obj.distListener_)
    delete(obj.distListener_);
end
obj.distListener_ = [];

if ~isempty(obj.distAxes_) && isvalid(obj.distAxes_)
    delete(obj.distAxes_);
end

if ~isempty(ax) && isvalid(ax) && ax.BeingDeleted == "off" && ~isempty(home) ...
        && isvalid(home.Parent)
    ax.Parent = home.Parent;
    if home.IsGrid
        ax.Layout.Row = home.Row;
        ax.Layout.Column = home.Column;
    else
        ax.OuterPosition = home.Position;
    end
end

if ~isempty(obj.distGrid_) && isvalid(obj.distGrid_)
    delete(obj.distGrid_);
end

obj.distAxes_ = [];
obj.distGrid_ = [];
obj.distHome_ = [];
obj.h_distBars_ = [];
obj.h_distRange_ = [];
obj.h_distMedian_ = [];
obj.h_distMean_ = [];
end
