function DefineRosterFile(self)
% DefineRosterFile(self)
% Prompt for and persist the subject roster file this rig uses.
%
% A lab shares one roster by putting it on a network drive and pointing every
% rig at the same file. Unset, each workstation keeps a private roster under
% prefdir.
%
% uiputfile rather than uigetfile: naming a roster that does not exist yet is
% the normal way to start one, and the file is created on the first mutation.
%
% See also: epsych.SubjectRoster.setConfiguredFile, epsych.RunExpt.OpenSubjectManager
arguments
    self
end

current = epsych.SubjectRoster.configuredFile();
% The configured roster may live on a share that is currently unreachable, in
% which case opening the dialog there would hang or fail; fall back to the data
% path but keep the file name.
[startDir, base, baseExt] = fileparts(current);
if isempty(startDir) || ~isfolder(startDir)
    startDir = char(self.dfltDataPath);
end
suggested = fullfile(startDir, [base baseExt]);

ext = epsych.SubjectRoster.FILE_EXTENSION;

ontop = self.AlwaysOnTop(false);
[fn, pn] = uiputfile( ...
    {['*' ext], ['Subject Roster (*' ext ')']; '*.*', 'All Files (*.*)'}, ...
    'Select or Name a Subject Roster', suggested);
self.AlwaysOnTop(ontop);

if isequal(fn, 0), return, end

ffn = fullfile(pn, fn);

try
    epsych.SubjectRoster.setConfiguredFile(ffn);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure1, ME.message, 'Subject Roster', 'Icon', 'error');
    return
end

if isfile(ffn)
    self.setStatus(sprintf('Subject roster: %s', ffn));
else
    self.setStatus(sprintf('Subject roster: %s', ffn), ...
        'the file will be created when you add your first subject.');
end
