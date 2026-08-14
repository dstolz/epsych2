function reloadIfStale_(self)
% reloadIfStale_(self)
% Re-read the file when another process has rewritten it since we last looked.
%
% This is the whole basis of shared-file safety: mutations apply to what is
% currently on disk, not to what this rig happened to read minutes ago. There
% is no watcher and no polling timer — staleness is checked here, on window
% open, and on an explicit Refresh.
%
% See also: epsych.SubjectRoster.stamp_, epsych.SubjectRoster.mutate_
arguments
    self
end

current = epsych.SubjectRoster.stamp_(self.FilePath);

if isequal(current, self.FileStamp_), return, end

vprintf(2, 'Subject roster changed on disk; re-reading before applying.');
self.reload();
