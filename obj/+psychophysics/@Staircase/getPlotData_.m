function [x, y, c, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = getPlotData_(obj)
% [x, y, c, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = getPlotData_(obj)
% Compute plotted data vectors and colors for staircase history plot.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   x, y — plotted trial indices and stimulus values
%   c — Nx3 RGB colors for each point (direction-coded)
%   xStep, yStep, cStep — step markers (subset of points with step direction)
%   xRevUp, yRevUp — reversal markers (up)
%   xRevDown, yRevDown — reversal markers (down)

x = nan;
y = nan;
c = zeros(1,3);
xStep = nan;
yStep = nan;
cStep = zeros(1,3);
xRevUp = nan;
yRevUp = nan;
xRevDown = nan;
yRevDown = nan;

trialValue = obj.columnize_(obj.stimulusValues);
if isempty(trialValue)
    return
end

trialIndex  = obj.columnize_(1:obj.trialCount);
direction   = obj.columnize_(obj.StepDirection);

valid = ~isnan(trialIndex) & ~isnan(trialValue);
if ~any(valid)
    return
end

x = trialIndex(valid);
y = trialValue(valid);
c = obj.directionColors_(direction(valid));

stepMask = valid & ~isnan(direction) & direction ~= 0;
if any(stepMask)
    xStep = trialIndex(stepMask);
    yStep = trialValue(stepMask);
    cStep = obj.directionColors_(direction(stepMask));
end

ridx = obj.columnize_(obj.ReversalIdx);
rdir = obj.columnize_(obj.ReversalDirection);
if isempty(ridx) || isempty(rdir)
    return
end

n = min(numel(ridx), numel(rdir));
ridx = ridx(1:n);
rdir = rdir(1:n);

revMask = ~isnan(ridx) & ridx >= 1 & ridx <= numel(trialValue) & isfinite(rdir);
ridx = ridx(revMask);
rdir = rdir(revMask);

if isempty(ridx)
    return
end

upMask = rdir > 0;
if any(upMask)
    xRevUp = trialIndex(ridx(upMask));
    yRevUp = trialValue(ridx(upMask));
end

downMask = rdir < 0;
if any(downMask)
    xRevDown = trialIndex(ridx(downMask));
    yRevDown = trialValue(ridx(downMask));
end
