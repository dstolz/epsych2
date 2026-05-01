function trigger_stim_playback(obj)
% trigger_stim_playback(obj) - Pulse the trigger parameter for the active buffer slot.
% Writes 1 then 0 to x_Trigger_<N>. Records lastTrigTime and samples
% the next ISI from the global ISI range.
% No-op if hardware parameters are not available.

if ~obj.HardwareAvailable
    % Record timing even without hardware so ISI logic still works
    obj.lastTrigTime = obj.timeSinceStart;
    obj.get_isi_;
    return
end

trigName = sprintf('x_Trigger_%d', obj.TrigBufferID);

obj.PARAMS.(trigName).Value = 1;
obj.lastTrigTime = obj.timeSinceStart;
obj.PARAMS.(trigName).Value = 0;

obj.get_isi_;

vprintf(3, 'StimPlayer:trigger_stim_playback: slot=%d  lastTrigTime=%.3f s', ...
    obj.TrigBufferID, obj.lastTrigTime);
end
