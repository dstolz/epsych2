function timer_runtimefcn(obj, src, ~)
% timer_runtimefcn(obj, src) - Main playback loop; called every timer period.
% Waits until the ISI has elapsed, triggers the current buffer, advances
% the bank selection, and pre-loads the next buffer.

try
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
    presentedIdx = obj.nextSPOIdx;

    % Trigger hardware (no-op if hardware unavailable)
    obj.trigger_stim_playback;

    % Advance the current bank item's internal counter
    obj.CurrentSPObj.increment;
    obj.advance_variant_(presentedIdx);

    obj.trialCount_ = obj.trialCount_ + 1;

    % Select next
    obj.nextSPOIdx = obj.select_next_idx;

    obj.update_counter_;
    obj.refresh_combo_controls_;

    if obj.nextSPOIdx < 1
        % All reps done; let timer_stopfcn handle cleanup
        stop(obj.Timer);
        return
    end

    % Pre-load next buffer (into the non-triggered buffer slot)
    obj.update_buffer;
catch ME
    if ~isempty(obj.Timer) && isvalid(obj.Timer)
        stop(obj.Timer);
    end
    obj.report_gui_error_(ME, "Playback Runtime Error", ...
        "StimPlayer encountered an error during playback and has stopped.");
end
end
