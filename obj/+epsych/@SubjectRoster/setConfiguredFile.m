function report = setConfiguredFile(filePath, options)
% report = epsych.SubjectRoster.setConfiguredFile(filePath)
% report = epsych.SubjectRoster.setConfiguredFile(filePath, AdoptLegacy=true)
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
% Options:
%   AdoptLegacy - copy the pre-2026-08-14 per-user roster into this path when
%                 this is the FIRST file ever configured here and the target
%                 does not exist yet (default false). Off by default so a
%                 script or a test that names a fresh roster gets a fresh
%                 roster; the operator-facing choosers pass true, which is what
%                 carries an existing rig's records forward exactly once.
%
% Returns:
%   report - struct with fields FilePath (the absolute path stored), Existed
%            (the file was already there), Migrated, and MigratedFrom.
%
% Throws:
%   epsych:SubjectRoster:PathIsFolder
%   epsych:SubjectRoster:FolderNotWritable
%
% See also: epsych.SubjectRoster.configuredFile, epsych.SubjectRoster.legacyFile,
%   epsych.RunExpt.DefineRosterFile
arguments
    filePath (1,:) char
    options.AdoptLegacy (1,1) logical = false
end

report = struct('FilePath','', 'Existed',false, 'Migrated',false, 'MigratedFrom','');

filePath = strtrim(filePath);

if isempty(filePath)
    if ispref('ep_RunExpt_Subjects', 'RosterFile')
        rmpref('ep_RunExpt_Subjects', 'RosterFile');
    end
    vprintf(1, 'Subject roster path cleared; this workstation has no roster configured.');
    return
end

wasConfigured = epsych.SubjectRoster.isConfigured();

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

% Adopt the old per-user file, once. Only on the very first choice: re-pointing
% a configured rig at a new empty file is a deliberate fresh start, and quietly
% filling it with records from a file the operator has stopped using would be
% the opposite of what they asked for.
if options.AdoptLegacy && ~wasConfigured && ~report.Existed
    legacy = epsych.SubjectRoster.legacyFile();
    if ~isempty(legacy) && ~strcmpi(legacy, filePath)
        try
            copyfile(legacy, filePath);
            report.Migrated     = true;
            report.MigratedFrom = legacy;
            vprintf(1, 'Adopted the existing per-user roster into %s (copied from %s; the original was left in place).', ...
                filePath, legacy);
        catch ME
            % Not fatal: the operator still gets the roster they named, empty.
            vprintf(0, 1, ME);
            vprintf(0, 1, 'The existing roster at %s could not be copied to %s; starting empty.', ...
                legacy, filePath);
        end
    end
end

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
