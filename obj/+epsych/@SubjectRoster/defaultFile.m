function f = defaultFile()
% f = epsych.SubjectRoster.defaultFile()
% Per-user fallback roster path, used when no shared file is configured.
%
% Lives under prefdir so it survives a repository move and never lands in the
% working directory. The folder is not created here: the file appears on the
% first mutation, so merely opening the manager leaves no trace on disk.
%
% Returns:
%   f - full path to the fallback .esub file.
%
% See also: epsych.SubjectRoster.configuredFile, epsych.SubjectRoster.setConfiguredFile

f = fullfile(prefdir, 'epsych', ['subjects' epsych.SubjectRoster.FILE_EXTENSION]);
