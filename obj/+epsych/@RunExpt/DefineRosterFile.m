function DefineRosterFile(self)
% DefineRosterFile(self)
% Prompt for and persist the subject roster file this rig uses.
%
% A lab shares one roster by putting it on a network drive and pointing every
% rig at the same file; a rig that works alone keeps its own. There is no
% default and no fallback -- see epsych.SubjectRoster.configuredFile -- so
% until this has been answered once, Subjects & Projects has nowhere to save
% and asks for itself at the first project.
%
% uiputfile rather than uigetfile: naming a roster that does not exist yet is
% the normal way to start one, and the file is created on the first mutation.
%
% See also: epsych.SubjectRoster.setConfiguredFile, epsych.RunExpt.OpenSubjectManager
arguments
    self
end

current = epsych.SubjectRoster.configuredFile();
if isempty(current)
    current = ['subjects' epsych.SubjectRoster.FILE_EXTENSION];
end
% The configured roster may live on a share that is currently unreachable, in
% which case opening the dialog there would hang or fail; fall back to the data
% path but keep the file name.
[startDir, base, baseExt] = fileparts(current);
if isempty(startDir) || ~isfolder(startDir)
    startDir = char(self.DefaultDataPath);
end
suggested = fullfile(startDir, [base baseExt]);

ext = epsych.SubjectRoster.FILE_EXTENSION;

ontop = self.AlwaysOnTop(false);
[fn, pn] = uiputfile( ...
    {['*' ext], ['Subject Roster (*' ext ')']; '*.*', 'All Files (*.*)'}, ...
    'Select or Name a Subject Roster', suggested);
self.AlwaysOnTop(ontop);

if isequal(fn, 0), return, end

try
    % AdoptLegacy: the first file ever named here inherits whatever an older
    % build accumulated under prefdir, so upgrading a rig does not look like
    % losing its animals.
    report = epsych.SubjectRoster.setConfiguredFile(fullfile(pn, fn), AdoptLegacy = true);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ME.message, 'Subject Roster', 'Icon', 'error');
    return
end

if report.Migrated
    self.setStatus(sprintf('Subject roster: %s', report.FilePath), ...
        sprintf('the roster from %s was copied into it and left in place.', ...
        report.MigratedFrom));
elseif report.Existed
    self.setStatus(sprintf('Subject roster: %s', report.FilePath));
else
    self.setStatus(sprintf('Subject roster: %s', report.FilePath), ...
        'the file will be created when you add your first subject.');
end
