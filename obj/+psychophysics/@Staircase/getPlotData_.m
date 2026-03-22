function [x, y, c, xCatch, yCatch, cCatch, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = getPlotData_(obj)
% [x, y, c, xCatch, yCatch, cCatch, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = getPlotData_(obj)
% Compute plotted data vectors and colors for staircase history plot.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   x, y — plotted stimulus-trial indices and stimulus values
%   c — Nx1 hex colors for each stimulus point (response-code coded)
%   xCatch, yCatch, cCatch — catch-trial point positions and hex colors
%   xStep, yStep, cStep — step markers (subset of points with hex colors)
%   xRevUp, yRevUp — reversal markers (up)
%   xRevDown, yRevDown — reversal markers (down)

x = nan;
y = nan;
c = obj.NeutralColor;
xCatch = nan;
yCatch = nan;
cCatch = obj.NeutralColor;
xStep = nan;
yStep = nan;
cStep = obj.StepColor;
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
responseCodes = obj.columnize_(obj.responseCodes);
decodedResponses = epsych.BitMask.decode(responseCodes);

valid = ~isnan(trialIndex) & ~isnan(trialValue);
if ~any(valid)
    return
end

catchMask = valid & decodedResponses.(char(obj.CatchTrialType));
stimMask = valid & ~catchMask;

if any(stimMask)
    x = trialIndex(stimMask);
    y = trialValue(stimMask);
    c = obj.responseCodeColors_(responseCodes(stimMask));
end

if any(catchMask)
    xCatch = trialIndex(catchMask);
    yCatch = trialValue(catchMask);
    cCatch = obj.responseCodeColors_(responseCodes(catchMask));
end

stepMask = valid & ~isnan(direction) & direction ~= 0;
if any(stepMask)
    xStep = trialIndex(stepMask);
    yStep = trialValue(stepMask);
    cStep = obj.responseCodeColors_(responseCodes(stepMask));
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
