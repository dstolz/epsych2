function cancel(obj)
% obj.cancel()
% Kill all owned ffmpeg processes, discard their partial outputs, and stop
% the scheduler. Safe to call at any time, including when no batch is
% running (a no-op) and from delete().
arguments
    obj (1,1) util.VideoConverter
end

obj.cancelRequested_ = true;

timerActive = ~isempty(obj.timer_) && isvalid(obj.timer_) && strcmp(obj.timer_.Running, 'on');
if ~timerActive
    % No running scheduler tick will ever see cancelRequested_, so finish
    % the job ourselves (this is the path delete() takes).
    obj.killAll_();
    obj.finishBatch_('cancelled');
end
end
