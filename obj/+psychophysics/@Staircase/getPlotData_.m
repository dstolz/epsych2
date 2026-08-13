function plotData = getPlotData_(obj)
% plotData = getPlotData_(obj)
% Compute plotted data vectors and colors for staircase history plot.
%
% Every per-trial vector comes from obj.sessionVectors_, which extracts and
% decodes the session once; this function only masks and indexes it.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   plotData — struct with fields:
%       .main:   x, y, c (stimulus trials)
%       .catch:  x, y, c (catch trials)
%       .step:   x, y, c (step markers)
%       .revUp:  x, y    (reversal up markers)
%       .revDown:x, y    (reversal down markers)
%       .bitsPresent: logical, one per obj.Bits, true when that outcome is plotted


plotData.bitsPresent = false(1, numel(obj.Bits));
plotData.main.x = nan;
plotData.main.y = nan;
plotData.main.c = obj.NeutralColor;
plotData.catch.x = nan;
plotData.catch.y = nan;
plotData.catch.c = obj.NeutralColor;
plotData.step.x = nan;
plotData.step.y = nan;
plotData.step.c = obj.StepColor;
plotData.revUp.x = nan;
plotData.revUp.y = nan;
plotData.revDown.x = nan;
plotData.revDown.y = nan;


s = obj.sessionVectors_();

trialValue = obj.columnize_(s.stimValues);
if isempty(trialValue)
    return
end

trialIndex  = obj.columnize_(1:obj.trialCount);
direction   = obj.columnize_(obj.Results.StepDirection);

valid = ~isnan(trialIndex) & ~isnan(trialValue);

if ~any(valid)
    return
end


catchMask = valid & obj.columnize_(s.catchMask);
stimMask = valid & obj.columnize_(s.stimMask);

if any(stimMask)
    plotData.main.x = trialIndex(stimMask);
    plotData.main.y = trialValue(stimMask);
    plotData.main.c = obj.responseCodeColors_(s.decoded, stimMask);
end

if any(catchMask)
    plotData.catch.x = trialIndex(catchMask);
    plotData.catch.y = trialValue(catchMask);
    plotData.catch.c = obj.responseCodeColors_(s.decoded, catchMask);
end

% Outcomes actually on screen drive which color swatches the legend names.
plottedMask = stimMask | catchMask;
if any(plottedMask) && ~isempty(s.decoded)
    for idx = 1:numel(obj.Bits)
        bitMask = s.decoded.(char(obj.Bits(idx)));
        if numel(bitMask) ~= numel(plottedMask), continue; end
        plotData.bitsPresent(idx) = any(bitMask(plottedMask));
    end
end

% The halo only marks that the staircase moved; the trial marker it sits
% behind already carries the outcome color, so it stays a single neutral hue.
stepMask = valid & ~isnan(direction) & direction ~= 0;
if any(stepMask)
    plotData.step.x = trialIndex(stepMask);
    plotData.step.y = trialValue(stepMask);
    plotData.step.c = repmat(obj.NeutralColor, sum(stepMask), 1);
end


ridx = obj.columnize_(obj.Results.ReversalIdx);
rdir = obj.columnize_(obj.Results.ReversalDirection);
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
    plotData.revUp.x = trialIndex(ridx(upMask));
    plotData.revUp.y = trialValue(ridx(upMask));
end

downMask = rdir < 0;
if any(downMask)
    plotData.revDown.x = trialIndex(ridx(downMask));
    plotData.revDown.y = trialValue(ridx(downMask));
end
