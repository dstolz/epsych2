function k = stamp_(filePath)
% k = epsych.SubjectRoster.stamp_(filePath)
% Cheap identity key for a file: path, mtime, and size.
%
% Mirrors the memoization key in epsych.Runtime.phaseCache (localKey). Any of
% the three changing means another process rewrote the file, which is the only
% signal a shared roster gets that it has gone stale — there is no watcher.
%
% Parameters:
%   filePath - full path; need not exist.
%
% Returns:
%   k - struct with path/datenum/bytes, or [] when the file is absent.
%
% See also: epsych.SubjectRoster.reloadIfStale_, epsych.Runtime.phaseCache
arguments
    filePath (1,:) char
end

k = [];
d = dir(filePath);
if isempty(d) || d(1).isdir
    return
end

k = struct('path', lower(filePath), 'datenum', d(1).datenum, 'bytes', d(1).bytes);
