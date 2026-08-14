function tf = acquireLock_(self)
% tf = acquireLock_(self)
% Take the advisory lock guarding a reload-then-write cycle.
%
% Honest about what this is: MATLAB has no atomic create-exclusive open, so the
% check-then-create below has a window. The lock NARROWS the race; it does not
% close it. The real protection is that every mutation reloads first and writes
% the whole model back, so two rigs adding different records cannot lose either
% one — the second write already contains the first.
%
% A lock older than LOCK_STALE_SECONDS is broken: a rig that crashed mid-write
% must not wedge the whole lab.
%
% Returns:
%   tf - true when the lock is held (or was broken as stale). False only means
%        another rig is mid-write; the caller proceeds anyway, because blocking
%        a rig is worse than the narrow race this covers.
%
% See also: epsych.SubjectRoster.releaseLock_, epsych.SubjectRoster.mutate_
arguments
    self
end

tf = false;
lockFile = [self.FilePath '.lock'];

d = dir(lockFile);
if ~isempty(d) && ~d(1).isdir
    ageSeconds = seconds(datetime('now') - datetime(d(1).datenum, ConvertFrom='datenum'));
    if ageSeconds < epsych.SubjectRoster.LOCK_STALE_SECONDS
        vprintf(2, 'Subject roster is locked by another session (%.0f s old): %s', ...
            ageSeconds, lockFile);
        return
    end
    vprintf(1, 'Breaking a stale subject-roster lock (%.0f s old): %s', ageSeconds, lockFile);
end

try
    fid = fopen(lockFile, 'w');
    if fid < 0, return, end
    fprintf(fid, 'host=%s%suser=%s%spid=%d%stime=%s%s', ...
        getenv('COMPUTERNAME'), newline, ...
        getenv('USERNAME'), newline, ...
        feature('getpid'), newline, ...
        char(datetime('now', Format='yyyy-MM-dd HH:mm:ss')), newline);
    fclose(fid);
catch ME
    vprintf(2, ME);
    return
end

self.LockHeld_ = lockFile;
tf = true;
