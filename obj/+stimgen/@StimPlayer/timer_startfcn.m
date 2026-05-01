function timer_startfcn(obj, ~, ~)
% timer_startfcn(obj) - Initialize state when the playback timer starts.
% Resets all bank item rep counts, selects the first stimulus,
% pre-loads the first buffer, and records the start time.

% Reset all rep counts
for i = 1:numel(obj.StimPlayObjs)
    obj.StimPlayObjs(i).reset;
end

% Clear presentation log
obj.StimOrder     = double.empty(0,1);
obj.StimOrderTime = double.empty(0,1);

obj.trialCount_ = 0;

% Select the first stimulus
obj.nextSPOIdx = obj.select_next_idx;

if obj.nextSPOIdx < 1
    % Nothing to play; stop immediately
    stop(obj.Timer);
    return
end

% Pre-load the first buffer
obj.update_buffer;

% Set ISI for the first interval
obj.get_isi_;

obj.firstTrigTime = now;
obj.lastTrigTime  = 0;

obj.update_counter_;
vprintf(2, 'StimPlayer timer started.');
end
