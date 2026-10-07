function updateSlidingThreshold_(obj)
% updateSlidingThreshold_(obj)
% Draw the sliding threshold estimate as a light stepped line over the trace.
%
% Each sliding block of ThresholdFromLastNReversals reversals has a threshold
% that becomes known at its last reversal and holds until the next one, so
% the line steps at each reversal and runs on to the latest trial. It starts
% only once one whole block exists, as the title's statistics do.
%
% Parameters:
%   obj — psychophysics.Staircase instance

h = obj.h_thrslide;
if isempty(h) || ~isvalid(h)
    return
end

x = nan;
y = nan;
if obj.ShowSlidingThreshold
    t = obj.Results.BlockThresholdTrial(:);
    v = obj.Results.BlockThreshold(:);
    if ~isempty(t) && numel(t) == numel(v)
        % Hold each estimate until the next block's, the last to the end.
        tEnd = [t(2:end); max(obj.trialCount, t(end))];
        x = reshape([t, tEnd].', [], 1);
        y = reshape([v, v].', [], 1);
    end
end
set(h, 'XData', x, 'YData', y, 'Visible', matlab.lang.OnOffSwitchState(obj.ShowSlidingThreshold));
end
