function report = assignToSession(self, runExpt, subjectIds, options)
% report = assignToSession(self, runExpt, subjectIds)
% report = assignToSession(self, runExpt, subjectIds, ProjectID=..., BoxIDs=..., Protocols=...)
% Put several roster subjects into a session's CONFIG in one action.
%
% Everything is validated before CONFIG is touched. A protocol that fails to
% load halfway through a batch must never leave a session half-populated, so
% the whole batch is refused instead. Box exhaustion aborts for the same
% reason: a partially applied batch is worse than one the operator repeats.
%
% This is the engine half of the manager's "Add Checked to Session" button. It
% takes no graphics and returns a report, so the GUI only renders the outcome
% and the whole path is testable headlessly.
%
% Parameters:
%   runExpt    - epsych.RunExpt to populate.
%   subjectIds - cellstr/string of SubjectIDs (or Names).
%
% Options:
%   ProjectID - project context used to resolve and remember protocols, and
%               whose BoxGUI is applied to the session's FUNCS.BoxFig.
%   BoxIDs    - per-subject box, NaN to auto-assign the lowest free one.
%   Protocols - per-subject .eprot path, '' to resolve from protocol memory.
%
% Returns:
%   report - struct with fields:
%              ok       - true when at least one subject was committed
%              aborted  - true when the batch was refused as a whole
%              added    - (1,:) struct: Name, BoxID, Protocol
%              skipped  - (1,:) struct: Name, reason
%              message  - one-line summary suitable for a status bar
%
% See also: epsych.RunExpt.appendSubjectToConfig_, epsych.SubjectRoster.lastProtocol
arguments
    self
    runExpt
    subjectIds
    options.ProjectID (1,:) char = ''
    options.BoxIDs double = []
    options.Protocols cell = {}
end

subjectIds = cellstr(string(subjectIds));
n = numel(subjectIds);

report = struct('ok', false, 'aborted', false, ...
    'added', struct('Name', {}, 'BoxID', {}, 'Protocol', {}), ...
    'skipped', struct('Name', {}, 'reason', {}), ...
    'message', '');

if n == 0
    report.message = 'No subjects were selected.';
    return
end

if isempty(runExpt) || ~isa(runExpt, 'epsych.RunExpt') || ~isvalid(runExpt)
    report.aborted = true;
    report.message = 'No session window is open, so there is nothing to add subjects to.';
    return
end

if runExpt.STATE >= PRGMSTATE.RUNNING
    report.aborted = true;
    report.message = 'A session is running. Halt it before changing the subject list.';
    return
end

if numel(options.BoxIDs) < n
    options.BoxIDs(end+1:n) = NaN;
end
if numel(options.Protocols) < n
    options.Protocols(end+1:n) = {''};
end

% --- gather what the session already occupies ---------------------------
takenBoxes = [];
takenNames = {};
if ~isempty(runExpt.CONFIG) && ~isempty(runExpt.CONFIG(1).SUBJECT)
    takenBoxes = arrayfun(@(c) c.SUBJECT.BoxID, runExpt.CONFIG);
    takenNames = arrayfun(@(c) c.SUBJECT.Name, runExpt.CONFIG, 'uni', 0);
end

% --- resolve every row before committing anything -----------------------
planned = struct('SubjectID', {}, 'Name', {}, 'BoxID', {}, 'Protocol', {});

for i = 1:n
    rec = self.findSubject(subjectIds{i});
    if isempty(rec)
        report.skipped(end+1) = struct('Name', subjectIds{i}, ...
            'reason', 'not in the roster');
        continue
    end

    if any(strcmpi(rec.Name, takenNames))
        report.skipped(end+1) = struct('Name', rec.Name, ...
            'reason', 'already in the session');
        continue
    end

    box = options.BoxIDs(i);
    if isnan(box)
        free = setdiff(1:16, [takenBoxes, [planned.BoxID]]);
        if isempty(free)
            report.aborted = true;
            report.message = sprintf(['All 16 boxes are taken, so "%s" and the rest ' ...
                'of the batch were not added. Nothing was changed.'], rec.Name);
            vprintf(0, 1, report.message);
            return
        end
        box = free(1);
    elseif any(box == [takenBoxes, [planned.BoxID]])
        report.skipped(end+1) = struct('Name', rec.Name, ...
            'reason', sprintf('box %d is already taken', box));
        continue
    end

    pfn = options.Protocols{i};
    if isempty(pfn)
        pfn = self.lastProtocol(rec.SubjectID, options.ProjectID);
    end
    % Having no protocol at all is a per-row skip: that subject simply is not
    % ready. A protocol that was named but cannot be used is different -- it
    % means the operator's intent cannot be honoured, so it aborts the batch
    % below rather than quietly running a subset.
    if isempty(pfn)
        report.skipped(end+1) = struct('Name', rec.Name, ...
            'reason', 'no protocol: none remembered and the project has no default');
        continue
    end

    planned(end+1) = struct('SubjectID', rec.SubjectID, 'Name', rec.Name, ...
        'BoxID', box, 'Protocol', pfn);
end

if isempty(planned)
    report.message = sprintf('Nothing was added; %d subject(s) could not be used.', ...
        numel(report.skipped));
    return
end

% --- load every protocol up front ---------------------------------------
% A failure here must not leave a half-populated CONFIG, so all of them are
% loaded before the first one is committed.
protocols = cell(1, numel(planned));
for i = 1:numel(planned)
    if ~isfile(planned(i).Protocol)
        report.aborted = true;
        report.message = sprintf(['The protocol for subject "%s" is missing, so the ' ...
            'whole batch was refused and nothing was changed: %s'], ...
            planned(i).Name, planned(i).Protocol);
        vprintf(0, 1, report.message);
        return
    end

    try
        protocols{i} = epsych.Protocol.load(planned(i).Protocol);
    catch ME
        vprintf(0, 1, ME);
        report.aborted = true;
        report.message = sprintf(['"%s" could not be loaded for subject "%s", so the ' ...
            'whole batch was refused and nothing was changed.'], ...
            planned(i).Protocol, planned(i).Name);
        return
    end
end

% --- commit --------------------------------------------------------------
for i = 1:numel(planned)
    runExpt.appendSubjectToConfig_( ...
        self.toSubject(planned(i).SubjectID, BoxID = planned(i).BoxID), ...
        planned(i).Protocol, protocols{i});

    report.added(end+1) = struct('Name', planned(i).Name, ...
        'BoxID', planned(i).BoxID, 'Protocol', planned(i).Protocol);

    if ~isempty(options.ProjectID)
        % The version comes from the object just loaded rather than a second
        % read of the file, and it is what protocolStatus later compares
        % against to notice that the protocol has been edited since.
        self.rememberProtocol(planned(i).SubjectID, options.ProjectID, ...
            planned(i).Protocol, planned(i).BoxID, ...
            Version = char(protocols{i}.meta.protocolVersion));
    end
end

% The project owns the behavior GUI, so committing its subjects is what puts
% that GUI on the session. Done after the commit, and only for a project that
% names one: a project that leaves the field empty must leave the session's own
% FUNCS.BoxFig alone rather than silently disabling the GUI.
boxGUI = localApplyBoxGUI(self, runExpt, options.ProjectID);

runExpt.UpdateSubjectList
runExpt.CheckReady

report.ok = true;
report.message = sprintf('Added %d subject(s) to the session.', numel(report.added));
if ~isempty(report.skipped)
    report.message = sprintf('%s %d skipped.', report.message, numel(report.skipped));
end
if ~isempty(boxGUI)
    report.message = sprintf('%s %s', report.message, boxGUI);
end
runExpt.setStatus(report.message);

% Multi-subject sessions reach a known limitation more easily than the
% one-at-a-time flow did: ExptDispatch takes hardware interfaces from
% CONFIG(1).PROTOCOL only, so subjects 2+ can dispatch into orphan objects.
% See plans/multi-subject-support.md.
if numel(report.added) > 1
    vprintf(1, ['Added %d subjects to one session. Multi-subject hardware dispatch ' ...
        'is a known open issue: interfaces come from the first subject''s protocol ' ...
        '(see plans/multi-subject-support.md).'], numel(report.added));
end

end

% -----------------------------------------------------------------------
function note = localApplyBoxGUI(self, runExpt, projectId)
% Put the project's behavior GUI on the session, returning a one-clause note
% for the report when it changed anything.
%
% The three states of a project's BoxGUI field: empty inherits whatever the
% session already has, BOXGUI_NONE disables the GUI, anything else names the
% function epsych.RunExpt.PsychTimerStart will feval. An unresolvable name is
% still applied -- it is the operator's stated intent, and a lab that adds its
% GUI to the path later would be badly served by having it silently dropped --
% but it is logged now rather than at run start.
note = '';
if isempty(projectId), return, end

p = self.findProject(projectId);
if isempty(p) || isempty(p.BoxGUI), return, end

if strcmpi(p.BoxGUI, epsych.SubjectRoster.BOXGUI_NONE)
    wanted = '';
else
    wanted = p.BoxGUI;
end

% A session may carry its box GUI as a handle rather than a name (DefineBoxFig
% accepts one), and [] rather than '' when disabled.
current = runExpt.FUNCS.BoxFig;
if isa(current, 'function_handle'), current = func2str(current); end
if strcmp(char(current), wanted), return, end

runExpt.FUNCS.BoxFig = wanted;

if isempty(wanted)
    note = sprintf('Project "%s" runs no box GUI.', p.Name);
else
    note = sprintf('Box GUI: %s', wanted);
    if isempty(which(wanted))
        vprintf(0, 1, ['Project "%s" names box GUI "%s", which is not on the path. ' ...
            'The session will start without it.'], p.Name, wanted);
    end
end
vprintf(1, 'Box GUI for project "%s": %s', p.Name, note);
end
