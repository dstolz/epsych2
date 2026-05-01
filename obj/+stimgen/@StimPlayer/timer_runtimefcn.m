function timer_runtimefcn(obj, src, ~)
% timer_runtimefcn(obj, src) - Main playback loop; called every timer period.
% Waits until the ISI has elapsed, triggers the current buffer, advances
% the bank selection, and pre-loads the next buffer.

if obj.nextSPOIdx < 1
    return  % all reps done; waiting for timer_stopfcn to fire
end

isi = obj.currentISI;
ts  = obj.timeSinceStart;

% Early return if ISI hasn't nearly elapsed (avoid busy-wait overhead)
if ts - obj.lastTrigTime - isi < src.Period - 0.01
    return
end

% Spin until ISI has exactly elapsed
while obj.timeSinceStart - obj.lastTrigTime < isi, end

% Log presentation
obj.StimOrder(end+1, 1)     = obj.nextSPOIdx;
obj.StimOrderTime(end+1, 1) = obj.timeSinceStart;

% Trigger hardware (no-op if hardware unavailable)
obj.trigger_stim_playback;

% Advance the current bank item's internal counter
obj.CurrentSPObj.increment;

obj.trialCount_ = obj.trialCount_ + 1;

% Select next
obj.nextSPOIdx = obj.select_next_idx;

obj.update_counter_;

if obj.nextSPOIdx < 1
    % All reps done; let timer_stopfcn handle cleanup
    stop(obj.Timer);
    return
end

% Pre-load next buffer (into the non-triggered buffer slot)
obj.update_buffer;
end
