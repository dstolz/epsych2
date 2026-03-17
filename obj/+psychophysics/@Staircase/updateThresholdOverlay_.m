function updateThresholdOverlay_(obj)
% updateThresholdOverlay_(obj)
% Update the threshold line and confidence region overlay.
%
% Parameters:
%   obj — psychophysics.Staircase instance

if isempty(obj.h_thrline) || ~isvalid(obj.h_thrline)
    return
end

if isempty(obj.Threshold) || ~isscalar(obj.Threshold) || ~isfinite(obj.Threshold) || isempty(obj.ReversalIdx)
    set(obj.h_thrline,'XData',nan,'YData',nan)
    set(obj.h_thrreg,'XData',nan,'YData',nan)
    return
end

ridx = obj.ReversalIdx(:);
if isempty(ridx)
    set(obj.h_thrline,'XData',nan,'YData',nan)
    set(obj.h_thrreg,'XData',nan,'YData',nan)
    return
end

startIdx = max(1, numel(ridx) - obj.ThresholdFromLastNReversals + 1);
xThr = [ridx(startIdx) ridx(end)];
yThr = [1 1]*obj.Threshold;
set(obj.h_thrline,'XData',xThr,'YData',yThr)

yThrStd = obj.ThresholdStd;
set(obj.h_thrreg,'XData',[xThr(1) xThr(2) xThr(2) xThr(1)], ...
    'YData',[yThr(1)-yThrStd, yThr(2)-yThrStd, yThr(2)+yThrStd, yThr(1)+yThrStd])
