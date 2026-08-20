function report = setConfiguredFile(filePath)
% report = epsych.SubjectRoster.setConfiguredFile(filePath)
% Point this workstation at a roster file.
%
% Pass '' to clear the preference, which leaves the workstation with no roster
% at all rather than falling back to one: there is no default location, and
% inventing one is what this replaced. The file itself need not exist -- it is
% created on the first mutation, which is what lets an operator name a new
% shared roster before there is anything to put in it.
%
% The path is validated here rather than at the first save, so an operator who
% names something unusable learns about it while the file dialog is still in
% mind rather than when a project they just filled in fails to persist.
%
% Parameters:
%   filePath - full path to a .esub file, or '' to clear. A relative path is
%              resolved against the current folder and stored absolute, since
%              the preference outlives whatever folder MATLAB was in.
%
% Returns:
%   report - struct with fields FilePath (the absolute path stored) and
%            Existed (the file was already there).
%
% Throws:
%   epsych:SubjectRoster:PathIsFolder
%   epsych:SubjectRoster:FolderNotWritable
%
% See also: epsych.SubjectRoster.configuredFile,
%   epsych.RunExpt.DefineRosterFile
arguments
    filePath (1,:) char
end

report = struct('FilePath','', 'Existed',false);

filePath = strtrim(filePath);

if isempty(filePath)
    if ispref('ep_RunExpt_Subjects', 'RosterFile')
        rmpref('ep_RunExpt_Subjects', 'RosterFile');
    end
    vprintf(1, 'Subject roster path cleared; this workstation has no roster configured.');
    return
end

if ~localIsAbsolute(filePath)
    filePath = fullfile(pwd, filePath);
    vprintf(2, 'Relative roster path resolved to: %s', filePath);
end

% movefile onto a directory succeeds by moving the temp file INSIDE it, so a
% folder target would look like a working roster that saves nothing.
if isfolder(filePath)
    error('epsych:SubjectRoster:PathIsFolder', ...
        'That is a folder, not a roster file: %s', filePath);
end

[folder, base, ext] = fileparts(filePath);
if isempty(ext)
    ext = epsych.SubjectRoster.FILE_EXTENSION;
    filePath = fullfile(folder, [base ext]);
    vprintf(2, 'Roster path had no extension; using %s', filePath);
end

% Created now rather than on the first save: a roster named into a folder that
% cannot be made is a choice the operator wants to hear about immediately.
if ~isempty(folder) && ~isfolder(folder)
    [ok, msg] = mkdir(folder);
    if ~ok
        error('epsych:SubjectRoster:FolderNotWritable', ...
            'The folder for the roster could not be created (%s): %s', msg, folder);
    end
    vprintf(1, 'Created folder for the subject roster: %s', folder);
end

report.FilePath = filePath;
report.Existed  = isfile(filePath);

setpref('ep_RunExpt_Subjects', 'RosterFile', filePath);
vprintf(1, 'Subject roster file set to: %s', filePath);

end

% -----------------------------------------------------------------------
function tf = localIsAbsolute(p)
% True for a rooted path. Windows accepts a drive letter or a UNC share; every
% other platform means a leading slash.
if ispc
    tf = ~isempty(regexp(p, '^([a-zA-Z]:[\\/]|\\\\|//)', 'once'));
else
    tf = startsWith(p, '/');
end
end
