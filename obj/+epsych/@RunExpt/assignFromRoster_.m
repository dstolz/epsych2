function assignFromRoster_(self, project, opts)
% assignFromRoster_(self, project, opts)
% Assemble the session from a roster project: the constructor's scripted
% launch path.
%
% Everything routes through epsych.SubjectRoster.assignToSession, so a
% scripted session inherits the whole membership model -- protocol memory,
% the session settings each membership carries, and the refusal when the
% chosen subjects' settings disagree. A script has no modal, so every refusal
% is an error here rather than a report.
%
% Parameters:
%   project - roster project Name or ProjectID.
%   opts    - the constructor's option struct; Subjects, Boxes, Protocols,
%             RosterFile, and Run are read here.
%
% Throws:
%   epsych:RunExpt:NoRoster    - no roster file is configured or readable.
%   epsych:RunExpt:NoProject   - nothing in the roster matches the name. A
%                                stale epsych.RunExpt('x.ecfg') call lands
%                                here, which is the right migration message.
%   epsych:RunExpt:NoSubjects  - the project has no committable members.
%   epsych:RunExpt:CommitRefused - assignToSession refused the batch.
%   epsych:RunExpt:NotReady    - Run was requested but the session did not
%                                reach READY.
%
% See also: epsych.SubjectRoster.assignToSession, epsych.RunExpt.RunExpt
arguments
    self
    project (1,1) string
    opts (1,1) struct
end

if isfield(opts, 'RosterFile') && strlength(opts.RosterFile) > 0
    R = epsych.SubjectRoster(char(opts.RosterFile));
else
    R = epsych.SubjectRoster();
end

if ~R.IsBound
    error('epsych:RunExpt:NoRoster', ...
        ['No subject roster is configured on this machine and no RosterFile ' ...
         'was given. Choose one in Subjects & Projects, or pass RosterFile.']);
end
if ~isempty(R.LoadError)
    error('epsych:RunExpt:NoRoster', 'The roster could not be read: %s', R.LoadError);
end

p = R.findProject(char(project));
if isempty(p)
    error('epsych:RunExpt:NoProject', ...
        'No project matches "%s" in the roster %s.', project, R.FilePath);
end

subjects = opts.Subjects;
if isempty(subjects)
    % The project's active members. subjectsInProject already filters
    % retired ones out by default.
    members = R.subjectsInProject(p.ProjectID);
    subjects = {members.Name};
end
subjects = cellstr(string(subjects));

if isempty(subjects)
    error('epsych:RunExpt:NoSubjects', ...
        'Project "%s" has no active members and no Subjects were named.', p.Name);
end

report = R.assignToSession(self, subjects, ProjectID = p.ProjectID, ...
    BoxIDs = opts.Boxes, Protocols = opts.Protocols);

if report.aborted || ~report.ok
    error('epsych:RunExpt:CommitRefused', '%s', report.message);
end
if ~isempty(report.skipped)
    % Partial commits succeed interactively, but a script that named its
    % subjects should hear that some were not used.
    names = strjoin({report.skipped.Name}, ', ');
    vprintf(0, 'Skipped: %s', names);
end

if isfield(opts, 'Run') && opts.Run
    if self.STATE >= PRGMSTATE.READY
        self.ExptDispatch("Run")
    else
        error('epsych:RunExpt:NotReady', ...
            ['Run was requested but the session is %s, not READY. ' ...
             'See the status bar and the self-test for what is missing.'], ...
            char(string(self.STATE)));
    end
end

end
