function releaseLock_(self)
% releaseLock_(self)
% Drop the advisory lock, if this object holds it.
%
% Best-effort: a lock that cannot be deleted expires on its own after
% LOCK_STALE_SECONDS, so a failure here is not worth reporting to the operator.
%
% See also: epsych.SubjectRoster.acquireLock_
arguments
    self
end

if isempty(self.LockHeld_), return, end

try
    if isfile(self.LockHeld_)
        delete(self.LockHeld_);
    end
catch ME
    vprintf(3, ME);
end

self.LockHeld_ = '';
