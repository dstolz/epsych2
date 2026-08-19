function attachPlotDestructionListeners_(obj)
% attachPlotDestructionListeners_(obj)
% Attach destruction/close listeners for the NAFC plot. An embedded axes
% belongs to its host GUI, so its destruction (or its figure's) must
% disable plotting here rather than leave stale handles behind.
%
% Parameters:
%   obj — psychophysics.NAFC instance

if isempty(obj.plotAxes_) || ~isvalid(obj.plotAxes_)
    return
end

if ~obj.plotOwnsFigure_
    obj.plotListeners_(end+1) = addlistener(obj.plotAxes_, "ObjectBeingDestroyed", @(~,~)obj.disablePlot());
    if ~isempty(obj.plotFigure_) && isvalid(obj.plotFigure_)
        obj.plotListeners_(end+1) = addlistener(obj.plotFigure_, "ObjectBeingDestroyed", @(~,~)obj.disablePlot());
    end
end
