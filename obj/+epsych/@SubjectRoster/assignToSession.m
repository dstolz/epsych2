function report = assignToSession(self, runExpt, subjectIds, options)
% report = assignToSession(self, runExpt, subjectIds)
% report = assignToSession(self, runExpt, subjectIds, ProjectID=..., BoxIDs=..., Protocols=...)
% Put several roster subjects into a session's CONFIG in one action.
%
% Everything is validated before CONFIG is touched. A protocol that fails to
% load halfway through a batch must never leave a session half-populated, so
% the whole batch is refused instead. Box exhaustion aborts for the same
% reason: a partially applied batch is worse than one the operator repeats.
% Diverged session settings across the batch abort too -- see the mismatch
% refusal below.
%
% What each subject RUNS is the .eprot's current content, except where its
% membership is pinned: revertProtocol pins a subject it put back on a version
% held only in the file's archive, and that version is loaded out of the
% archive here instead. A hold naming a version the file can no longer produce
% aborts the batch like any other unusable protocol.
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
%   ProjectID - project context used to resolve and remember protocols, and to
%               find each subject's MEMBERSHIP, which is what carries the
%               session settings (behavior GUI, data path, saving function,
%               timer callbacks and period, video and Intan recording paths).
%               A field the membership leaves empty inherits the built-in
%               default rather than being blanked. With no project context,
%               no settings are applied at all.
%   BoxIDs    - per-subject box, NaN to auto-assign the lowest free one.
%   Protocols - per-subject .eprot path, '' to resolve from protocol memory.
%   ReplaceExisting - true to make the batch the session's whole subject list:
%               whoever is already in CONFIG is removed as the new rows land.
%               The removal happens only once the batch is certain to commit,
%               so an aborted batch still leaves the session as it was. Boxes
%               and names held by the outgoing subjects are free to the batch,
%               which is what lets an operator re-add the same animal in the
%               same box. Default false: appending is what a script asking for
%               one more subject means, and the manager's "Add Checked to
%               Session" button is what asks for a replacement.
%
% Returns:
%   report - struct with fields:
%              ok       - true when at least one subject was committed
%              aborted  - true when the batch was refused as a whole
%              added    - (1,:) struct: Name, BoxID, Protocol
%              skipped  - (1,:) struct: Name, reason
%              mismatch - (1,:) struct: Field, Values, Names; filled when the
%                         batch was refused because the checked subjects carry
%                         different session settings
%              removed  - (1,:) cellstr of subjects the batch displaced
%              message  - one-line summary suitable for a status bar
%
% See also: epsych.RunExpt.appendSubjectToConfig_, epsych.SubjectRoster.lastProtocol,
%   epsych.SubjectRoster.updateMembership, epsych.SubjectRoster.reapplyTemplate
arguments
    self
    runExpt
    subjectIds
    options.ProjectID (1,:) char = ''
    options.BoxIDs double = []
    options.Protocols cell = {}
    options.ReplaceExisting (1,1) logical = false
end

subjectIds = cellstr(string(subjectIds));
n = numel(subjectIds);

report = struct('ok', false, 'aborted', false, ...
    'added', struct('Name', {}, 'BoxID', {}, 'Protocol', {}), ...
    'skipped', struct('Name', {}, 'reason', {}), ...
    'mismatch', struct('Field', {}, 'Values', {}, 'Names', {}), ...
    'removed', {{}}, ...
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
% Under ReplaceExisting these subjects are on their way out, so what they hold
% is not "taken": treating it as such would skip an animal the operator ticked
% because an earlier version of the same row is still in the table.
occupants = {};
if ~isempty(runExpt.CONFIG) && ~isempty(runExpt.CONFIG(1).SUBJECT)
    occupants = arrayfun(@(c) c.SUBJECT.Name, runExpt.CONFIG, 'uni', 0);
end

takenBoxes = [];
takenNames = {};
if ~options.ReplaceExisting && ~isempty(occupants)
    takenBoxes = arrayfun(@(c) c.SUBJECT.BoxID, runExpt.CONFIG);
    takenNames = occupants;
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

% --- resolve session config per planned subject -------------------------
% The membership is where a subject's session settings live, so each planned
% subject's membership in the chosen project is resolved now -- before any
% side effect, so a refusal leaves nothing half-applied. A subject with no
% membership resolves to all-inherit (built-in defaults), noted in the report.
% With no project context ('' -- the All Projects view) no settings are
% applied, matching how protocols are resolved.
memberships = {};
projectName = '';
configNotes = {};
if ~isempty(options.ProjectID)
    p = self.findProject(options.ProjectID);
    if ~isempty(p)
        projectName = p.Name;
        memberships = cell(1, numel(planned));
        for i = 1:numel(planned)
            m = self.findMembership(planned(i).SubjectID, p.ProjectID);
            if isempty(m)
                m = epsych.SubjectRoster.blankMembership_();
                configNotes{end+1} = sprintf(['"%s" has no membership in "%s"; ' ...
                    'built-in session defaults apply.'], planned(i).Name, p.Name);
            end
            memberships{i} = m;
        end

        % Mismatch refusal: the batch shares one session, so the memberships
        % must agree on the session-level settings. Raw values, not resolved:
        % memberships in one project are verbatim stamps of one template and
        % diverge only through a template edit between adds or a deliberate
        % per-subject edit -- exactly what must surface here.
        report.mismatch = localSessionMismatch(memberships, {planned.Name});
        if ~isempty(report.mismatch)
            report.aborted = true;
            report.message = localMismatchMessage(report.mismatch);
            vprintf(0, 1, report.message);
            return
        end
    end
end

% --- load every protocol up front ---------------------------------------
% A failure here must not leave a half-populated CONFIG, so all of them are
% loaded before the first one is committed.
%
% A pinned membership is the one case where the file's current content is not
% what loads: revertProtocol put this subject back on a version that lives in
% the file's archive without rewriting the shared file, so the version comes
% out of the archive instead. Everything downstream then agrees by itself --
% the object carries the pinned version, so RunExpt's subject list shows it
% and rememberProtocol records it back unchanged.
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

    pinned = localPinnedVersion(memberships, i, planned(i).Protocol);

    % A hold naming a version the file can no longer produce is the operator's
    % intent gone unhonourable, which aborts the batch here for the same reason
    % a named-but-unusable protocol does: running the wrong content is worse
    % than running nothing.
    if ~isempty(pinned) && ~epsych.Protocol.hasVersion(planned(i).Protocol, pinned)
        report.aborted = true;
        report.message = sprintf(['Subject "%s" is held on protocol version %s, which ' ...
            '%s no longer holds or archives, so the whole batch was refused and nothing ' ...
            'was changed. Update the subject to release the hold.'], ...
            planned(i).Name, pinned, planned(i).Protocol);
        vprintf(0, 1, report.message);
        return
    end

    try
        if isempty(pinned)
            protocols{i} = epsych.Protocol.load(planned(i).Protocol);
        else
            protocols{i} = epsych.Protocol.loadVersion(planned(i).Protocol, pinned);
            vprintf(1, 'Subject "%s" is held on %s of "%s"; loaded it from the version archive.', ...
                planned(i).Name, pinned, planned(i).Protocol);
        end
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
% Clearing happens here and not a line earlier: every check that can refuse the
% batch has passed, so from this point the session is guaranteed to end up with
% the new list rather than with no subjects at all.
if options.ReplaceExisting && ~isempty(occupants)
    report.removed = occupants;
    runExpt.ClearConfig();
    vprintf(1, 'Replaced the session subject list; removed %s.', ...
        strjoin(occupants, ', '));
end

for i = 1:numel(planned)
    runExpt.appendSubjectToConfig_( ...
        self.toSubject(planned(i).SubjectID, BoxID = planned(i).BoxID), ...
        planned(i).Protocol, protocols{i});

    report.added(end+1) = struct('Name', planned(i).Name, ...
        'BoxID', planned(i).BoxID, 'Protocol', planned(i).Protocol);

    if ~isempty(options.ProjectID)
        % The version comes from the object just loaded rather than a second
        % read of the file, and it is what protocolStatus later compares
        % against to notice that the protocol has been edited since. For a
        % pinned subject that object IS the held version, so recording it
        % leaves the hold exactly where it was.
        self.rememberProtocol(planned(i).SubjectID, options.ProjectID, ...
            planned(i).Protocol, planned(i).BoxID, ...
            Version = char(protocols{i}.meta.protocolVersion));
    end
end

% The membership owns the settings a paradigm decides -- behavior GUI, where
% data and recordings are written, which function saves them, which callbacks
% the timer runs and how fast -- so committing a subject is what puts them on
% the session. The batch was refused above unless every membership agrees, so
% any one of them speaks for all. Done after the commit, and only for the
% fields the membership actually names: an empty one must leave the session's
% own value alone rather than blanking it.
notes = configNotes;
if ~isempty(memberships)
    notes = [notes, localApplySessionDefaults(runExpt, memberships{1}, projectName)];
end

runExpt.UpdateSubjectList
runExpt.CheckReady

report.ok = true;
report.message = sprintf('Added %d subject(s) to the session.', numel(report.added));
if ~isempty(report.removed)
    report.message = sprintf('%s Removed %d already there.', ...
        report.message, numel(report.removed));
end
if ~isempty(report.skipped)
    report.message = sprintf('%s %d skipped.', report.message, numel(report.skipped));
end
if ~isempty(notes)
    report.message = sprintf('%s %s', report.message, strjoin(notes, ' '));
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
function version = localPinnedVersion(memberships, i, protocolPath)
% The version this row is HELD on, or '' when the file's own content is what
% should load.
%
% A hold only means anything for the file it was recorded against: an operator
% who names a different protocol for this commit has already moved the subject,
% and rememberProtocol releases the hold when the commit lands. Nor does it mean
% anything once the file has come back round to the held version, which a
% content restore elsewhere can do.
version = '';
if isempty(memberships) || numel(memberships) < i, return, end

m = memberships{i};
if ~m.ProtocolPinned || isempty(m.LastProtocolVersion), return, end
if ~localSamePath(m.LastProtocol, protocolPath), return, end
if strcmp(epsych.Protocol.versionOnDisk(protocolPath), m.LastProtocolVersion), return, end

version = m.LastProtocolVersion;
end

% -----------------------------------------------------------------------
function tf = localSamePath(a, b)
% Same protocol file by path text, the way the filesystem would read it.
a = char(a); b = char(b);
if isempty(a) || isempty(b), tf = false; return, end
a = strrep(a, '/', filesep); b = strrep(b, '/', filesep);
if ispc
    tf = strcmpi(a, b);
else
    tf = strcmp(a, b);
end
end

% -----------------------------------------------------------------------
function mis = localSessionMismatch(memberships, names)
% Compare the raw SESSION_FIELDS across the resolved memberships, returning
% one record per disagreeing field: the distinct values and, for each, which
% subjects carry it. isequaln so two "inherit" TimerPeriods (NaN) agree.
mis = struct('Field', {}, 'Values', {}, 'Names', {});
for f = epsych.SubjectRoster.SESSION_FIELDS
    vals = cellfun(@(m) m.(f{1}), memberships, 'uni', 0);

    groups = {};
    groupNames = {};
    for i = 1:numel(vals)
        k = find(cellfun(@(g) localSameValue(g, vals{i}), groups), 1);
        if isempty(k)
            groups{end+1} = vals{i};
            groupNames{end+1} = names(i);
        else
            groupNames{k} = [groupNames{k}, names(i)];
        end
    end

    if numel(groups) > 1
        mis(end+1) = struct('Field', f{1}, 'Values', {groups}, 'Names', {groupNames});
    end
end
end

% -----------------------------------------------------------------------
function tf = localSameValue(a, b)
% Two session-setting values agree. Both-empty counts as agreement whatever
% the shapes: a stamped '' comes back from a MAT round trip as 1x0 while a
% fresh record holds 0x0, and isequaln alone would call those different --
% turning two all-inherit memberships into a spurious refusal.
if isempty(a) && isempty(b)
    tf = true;
    return
end
tf = isequaln(a, b);
end

% -----------------------------------------------------------------------
function msg = localMismatchMessage(mis)
% Render the refusal for the status bar and the manager's modal: what differs,
% who carries what, and the two named fixes.
lines = cell(1, numel(mis));
for i = 1:numel(mis)
    parts = cell(1, numel(mis(i).Values));
    for k = 1:numel(mis(i).Values)
        parts{k} = sprintf('%s (%s)', localFormatValue(mis(i).Values{k}), ...
            strjoin(mis(i).Names{k}, ', '));
    end
    lines{i} = sprintf('%s: %s.', mis(i).Field, strjoin(parts, ' vs '));
end
msg = sprintf(['The checked subjects carry different session settings, so nothing ' ...
    'was added: %s Edit each subject''s Session Settings..., or Re-apply Project ' ...
    'Template, until they agree.'], strjoin(lines, ' '));
end

% -----------------------------------------------------------------------
function s = localFormatValue(v)
% One session-setting value as it should read in a refusal message.
if ischar(v) || isstring(v)
    if strlength(string(v)) == 0
        s = '(inherit)';
    else
        s = sprintf('"%s"', char(v));
    end
elseif isnumeric(v) && all(isnan(v(:)))
    s = '(inherit)';
else
    s = char(strjoin(string(v), ' '));
end
end

% -----------------------------------------------------------------------
function notes = localApplySessionDefaults(runExpt, m, projectName)
% Put the membership's session settings on the session, returning short
% clauses for the report describing what changed.
%
% Everything here is applied only when the membership names it: an empty field
% is "inherit the built-in default", which is also what a roster written
% before these fields existed says, so a membership that only cares about its
% protocol changes nothing. Values land on the session (FUNCS,
% DefaultDataPath, PATHS) and never in the machine preferences -- running one
% study must not redefine the rig's own defaults.
%
% Nothing here refuses a value. A path that does not exist or a function that
% is not on the path is the operator's stated intent; it is logged now, at the
% moment it is applied, rather than surfacing as a puzzle at run start.
notes = {};

boxNote = localApplyBehaviorGUI(runExpt, m, projectName);
if ~isempty(boxNote), notes{end+1} = boxNote; end

applied = {};

% Data save path: the root every subject's folder is created under.
if ~isempty(m.DefaultDataPath) && ~strcmp(char(runExpt.DefaultDataPath), m.DefaultDataPath)
    runExpt.DefaultDataPath = string(m.DefaultDataPath);
    applied{end+1} = 'data path';
    if ~isfolder(m.DefaultDataPath)
        vprintf(0, ['Project "%s" saves to "%s", which does not exist yet; ' ...
            'it is created at run start.'], projectName, m.DefaultDataPath);
    end
end

% Saving function: SaveFcn(RUNTIME), called after the run.
if ~isempty(m.SavingFcn) && ~strcmp(char(runExpt.FUNCS.SavingFcn), m.SavingFcn)
    runExpt.FUNCS.SavingFcn = m.SavingFcn;
    applied{end+1} = 'saving function';
    if isempty(which(m.SavingFcn))
        vprintf(0, 1, ['Project "%s" names saving function "%s", which is not on ' ...
            'the path. The session would end without saving.'], projectName, m.SavingFcn);
    end
end

% Timer lifecycle callbacks: the trial loop itself. A lab's custom loop names
% them on the project template, which stamps them here.
timerMap = {'TimerStartFcn','Start'; 'TimerRunTimeFcn','RunTime'; ...
            'TimerStopFcn','Stop';   'TimerErrorFcn','Error'};
changed = {};
for i = 1:size(timerMap,1)
    v = m.(timerMap{i,1});
    if isempty(v), continue, end
    if ~strcmp(char(runExpt.FUNCS.TIMERfcn.(timerMap{i,2})), v)
        runExpt.FUNCS.TIMERfcn.(timerMap{i,2}) = v;
        changed{end+1} = timerMap{i,2};
        if isempty(which(v))
            vprintf(0, 1, ['Subject''s membership names timer function "%s", which is not ' ...
                'on the path. The run would fail at %s.'], v, timerMap{i,2});
        end
    end
end
if ~isempty(changed)
    applied{end+1} = sprintf('timer %s function(s)', strjoin(changed, '/'));
end

% Timer period: read by CreateTimer at run start, so applying it here is enough.
if ~isnan(m.TimerPeriod) && ~isequal(runExpt.FUNCS.TimerPeriod, m.TimerPeriod)
    runExpt.FUNCS.TimerPeriod = m.TimerPeriod;
    applied{end+1} = 'timer period';
end

% Recording roots. Empty on the session means "fall back to the data path", so
% these are session state rather than preferences: the next session without a
% project must get the rig's own values back.
if ~isempty(m.VideoRootDir) && ~strcmp(runExpt.PATHS.VideoRootDir, m.VideoRootDir)
    runExpt.PATHS.VideoRootDir = m.VideoRootDir;
    applied{end+1} = 'video path';
end

if ~isempty(m.IntanRootDir) && ~strcmp(runExpt.PATHS.IntanRootDir, m.IntanRootDir)
    runExpt.PATHS.IntanRootDir = m.IntanRootDir;
    applied{end+1} = 'Intan path';
    if any(isspace(m.IntanRootDir))
        vprintf(0, 1, ['Project "%s" names Intan recording path "%s", which contains ' ...
            'spaces. RHX commands cannot express them and recording will fail.'], ...
            projectName, m.IntanRootDir);
    end
end

% The protocol's own settings file still wins over this one; see
% epsych.RunExpt.configureIntanRecorder_.
if ~isempty(m.IntanSettingsFile) && ~strcmp(runExpt.PATHS.IntanSettingsFile, m.IntanSettingsFile)
    runExpt.PATHS.IntanSettingsFile = m.IntanSettingsFile;
    applied{end+1} = 'Intan settings file';
end

if ~isempty(applied)
    vprintf(1, 'Project "%s" set the session %s.', projectName, strjoin(applied, ', '));
    notes{end+1} = sprintf('Project %s applied.', strjoin(applied, ', '));
end
end

% -----------------------------------------------------------------------
function note = localApplyBehaviorGUI(runExpt, m, projectName)
% Put the membership's behavior GUI on the session, returning a one-clause
% note for the report when it changed anything.
%
% The three states of a membership's BehaviorGUI field: empty inherits the
% built-in default, BEHAVIORGUI_NONE disables the GUI, anything else names the
% function epsych.RunExpt.PsychTimerStart will feval. An unresolvable name is
% still applied -- it is the operator's stated intent, and a lab that adds its
% GUI to the path later would be badly served by having it silently dropped --
% but it is logged now rather than at run start.
note = '';
if isempty(m.BehaviorGUI), return, end

if strcmpi(m.BehaviorGUI, epsych.SubjectRoster.BEHAVIORGUI_NONE)
    wanted = '';
else
    wanted = m.BehaviorGUI;
end

% [] rather than '' is how a session carries a disabled GUI, so go through
% char for the comparison.
if strcmp(char(runExpt.FUNCS.BehaviorGUI), wanted), return, end

runExpt.FUNCS.BehaviorGUI = wanted;

if isempty(wanted)
    note = sprintf('Project "%s" runs no behavior GUI.', projectName);
else
    note = sprintf('Behavior GUI: %s', wanted);
    if isempty(which(wanted))
        vprintf(0, 1, ['Project "%s" names behavior GUI "%s", which is not on the path. ' ...
            'The session will start without it.'], projectName, wanted);
    end
end
vprintf(1, 'Behavior GUI for project "%s": %s', projectName, note);
end
