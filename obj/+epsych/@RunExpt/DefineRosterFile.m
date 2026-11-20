function DefineRosterFile(self, mode)
% DefineRosterFile(self)
% DefineRosterFile(self, mode)
% Open an existing subject roster, or create a new one, and persist it as the
% roster this rig uses.
%
% A lab shares one roster by putting it on a network drive and pointing every
% rig at the same file; a rig that works alone keeps its own. There is no
% default and no fallback -- see epsych.SubjectRoster.configuredFile -- so
% until this has been answered once, Subjects & Projects has nowhere to save
% and asks for itself at the first project.
%
% Opening and creating are separate (gui.chooseRosterFile): one Save dialog
% for both made Windows ask "replace it?" whenever the operator picked the
% roster they meant to open.
%
% Parameters:
%   mode - "open", "create", or "ask" (default; asks which first).
%
% See also: gui.chooseRosterFile, epsych.SubjectRoster.setConfiguredFile,
%   epsych.RunExpt.OpenSubjectManager
arguments
    self
    mode (1,1) string {mustBeMember(mode, ["ask","open","create"])} = "ask"
end

ontop = self.AlwaysOnTop(false);
[file, mode] = gui.chooseRosterFile(self.H.figure1, Mode = mode, ...
    Current = epsych.SubjectRoster.configuredFile(), ...
    StartFolder = char(self.DefaultDataPath));
self.AlwaysOnTop(ontop);

if isempty(file), return, end

try
    report = epsych.SubjectRoster.setConfiguredFile(file);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ME.message, 'Subject Roster', 'Icon', 'error');
    return
end

if strcmp(mode, 'create') && ~report.Existed
    self.setStatus(sprintf('New subject roster: %s', report.FilePath), ...
        'the file will be created when you add your first subject.');
else
    self.setStatus(sprintf('Opened subject roster: %s', report.FilePath));
end
