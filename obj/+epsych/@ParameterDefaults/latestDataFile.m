function [file, row, message] = latestDataFile(subjectName, options)
% [file, row, message] = epsych.ParameterDefaults.latestDataFile(subjectName)
% [file, row, message] = epsych.ParameterDefaults.latestDataFile(subjectName, Roster=R, RunExpt=X)
% The subject's most recent saved session with at least one trial -- what the
% editor's Copy from Last Data File reads.
%
% Found through epsych.SessionFiles, so it looks everywhere a session could
% have been saved (the rig's data path, every project's and membership's, under
% every name the subject has had) and caches what it read. Preview runs and
% crash-recovery copies are passed over: a Preview is a test, and a recovery
% copy exists for every session that also saved normally.
%
% The newest file is not necessarily the right one -- a subject in two
% projects has two streams of sessions -- which is why the editor names the
% file and lets the operator pick another before anything is copied.
%
% Parameters:
%   subjectName - the subject's current Name.
%
% Options:
%   Roster, RunExpt - passed to epsych.SessionFiles.locations.
%
% Returns:
%   file    - full path, or "" when none was found.
%   row     - that file's epsych.SessionFiles summary (a one-row table), or [].
%   message - why none was found, or ''.
%
% See also: epsych.ParameterDefaults.readDataFile, epsych.SessionFiles.scan
arguments
    subjectName (1,1) string
    options.Roster = []
    options.RunExpt = []
end

file = "";
row = [];
message = '';

L = epsych.SessionFiles.locations(subjectName, Roster = options.Roster, ...
    RunExpt = options.RunExpt);
[T, rep] = epsych.SessionFiles.scan(L.Names, Roots = L.Roots);

if ~isempty(T)
    ok = T.IsSession & ~T.IsTest & T.Trials > 0 & T.Source == "Saved" ...
        & strlength(T.Error) == 0;
    T = T(ok, :);
end

if isempty(T)
    where = strjoin(rep.Folders, ', ');
    if strlength(where) == 0
        where = strjoin(L.Roots, ', ');
    end
    message = sprintf('No saved session with trials was found for "%s" (looked in %s).', ...
        subjectName, where);
    return
end

% scan() is newest first.
row = T(1, :);
file = row.File;
end
