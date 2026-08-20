function smoke_test_subject_roster()
% smoke_test_subject_roster()
% Exercise epsych.SubjectRoster headlessly: file round trip, many-to-many
% membership, per-project retire, protocol memory, the rename block, shared-file
% concurrency, atomic-write safety, the epsych.Subject seam, and the batch
% commit into epsych.RunExpt.CONFIG.
%
% Everything runs under a temporary roster; the user's preferences are restored
% on exit whether it passes or fails.
%
%   matlab -batch "cd('tmp'); smoke_test_subject_roster"
%
% See also: epsych.SubjectRoster, documentation/epsych/epsych_SubjectRoster.md

epsych_startup

% The roster path and the data root are both preferences this test writes.
% Snapshot first, then register the cleanup by value: onCleanup cannot call a
% nested function over variables assigned after it was created.
savedSubjectPrefs = localSavePrefs('ep_RunExpt_Subjects');
savedRunExptPrefs = localSavePrefs('RunExpt');

% Self-healing: a run killed before its cleanup leaves RosterFile pointing into
% tempdir, and every later run would faithfully restore that -- which is how a
% rig ends up silently aimed at a folder the OS has since deleted. A roster
% under tempdir is by definition a test artifact, so it is never put back.
savedSubjectPrefs = localDropTempRoster(savedSubjectPrefs);
cleanupPrefs = onCleanup(@() localRestoreAll(savedSubjectPrefs, savedRunExptPrefs));

root = fullfile(tempdir, 'epsych_roster_smoke');
if isfolder(root)
    rmdir(root, 's');
end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

rosterFile = fullfile(root, 'subjects.esub');
proto = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'tmp', 'TEST_NEW_PROTOCOL2.eprot');
assert(isfile(proto), 'Test protocol fixture is missing: %s', proto);

% 1. Round trip ------------------------------------------------------------
R = epsych.SubjectRoster(rosterFile);
p1 = R.addProject('ToneDetect', DefaultProtocol = proto, Notes = 'first study');
p2 = R.addProject('GapDetect');
s1 = R.addSubject(struct('Name','M001','Sex','Male','Species','Gerbil'));
s2 = R.addSubject(struct('Name','M002','Sex','Female','Species','Gerbil','Weight',61.5));
s3 = R.addSubject(struct('Name','M003','Sex','Male','Species','Mouse'));

R2 = epsych.SubjectRoster(rosterFile);
assert(numel(R2.Subjects) == 3 && numel(R2.Projects) == 2, 'Round trip lost records');
a = R2.findSubject('M001');
b = R2.findSubject('M002');
% NaN is "not measured" and must survive; this is the assertion that would
% have caught a JSON format choice, where NaN encodes as null.
assert(isnan(a.Weight), 'A NaN weight must round trip as NaN, not 0 or empty');
assert(b.Weight == 61.5, 'A measured weight must round trip exactly');
assert(isdatetime(a.Created) && ~isnat(a.Created), 'datetime fields must round trip');
fprintf('PASS: round trip preserves records, NaN weight, and datetimes\n');

% 2. Many-to-many membership ----------------------------------------------
R.assign(s1, p1); R.assign(s1, p2); R.assign(s2, p1); R.assign(s3, p2);

assert(numel(R.projectsForSubject(s1)) == 2, 'M001 should be in two projects');
assert(ismember('M001', {R.subjectsInProject(p1).Name}), 'M001 missing from p1');
assert(ismember('M001', {R.subjectsInProject(p2).Name}), 'M001 missing from p2');

R.unassign(s1, p1);
assert(~ismember('M001', {R.subjectsInProject(p1).Name}), 'unassign did not remove from p1');
assert(ismember('M001', {R.subjectsInProject(p2).Name}), 'unassign must not touch other projects');
assert(~isempty(R.findSubject(s1)), 'unassign must not delete the subject record');
R.assign(s1, p1);
fprintf('PASS: a subject lives in several projects independently\n');

% 3. Retire is per-project, not global -------------------------------------
R.setActive(s1, p2, false);
assert(~ismember('M001', {R.subjectsInProject(p2).Name}), 'Retired subject should be hidden');
assert(ismember('M001', {R.subjectsInProject(p2, IncludeRetired=true).Name}), ...
    'IncludeRetired should reveal it');
assert(ismember('M001', {R.subjectsInProject(p1).Name}), ...
    'Retiring from one project must leave the other active');
R.setActive(s1, p2, true);
assert(ismember('M001', {R.subjectsInProject(p2).Name}), 'Restore failed');
fprintf('PASS: retire and restore are per-membership\n');

% 4. Protocol memory and its fallback chain --------------------------------
R.rememberProtocol(s1, p2, 'C:\proto\gap.eprot', 3);
R3 = epsych.SubjectRoster(rosterFile);
assert(strcmp(R3.lastProtocol(s1, p2), 'C:\proto\gap.eprot'), ...
    'Membership protocol memory did not survive a reload');
assert(strcmp(R3.lastProtocol(s1, p1), proto), ...
    'Should fall back to the project default');
assert(isempty(R3.lastProtocol(s3, p2)), ...
    'No memory and no default should resolve to empty');
fprintf('PASS: protocol memory resolves membership then project default\n');

% 5. Rename is blocked once data exists ------------------------------------
dataRoot = fullfile(root, 'data');
mkdir(fullfile(dataRoot, 'M002'));
setpref('RunExpt', 'DataPath', dataRoot);

threw = false;
try
    R.updateSubject(s2, struct('Name','M002_renamed'));
catch ME
    threw = strcmp(ME.identifier, 'epsych:SubjectRoster:RenameBlocked');
end
assert(threw, 'Renaming a subject with existing data must be refused');
assert(strcmp(R.findSubject(s2).Name, 'M002'), 'A refused rename must leave the record alone');

rmdir(fullfile(dataRoot, 'M002'));
R.updateSubject(s2, struct('Name','M002_renamed'));
renamed = R.findSubject(s2);
assert(strcmp(renamed.Name, 'M002_renamed'), 'Rename should succeed with no data on disk');
assert(any(renamed.NameHistory == "M002"), 'NameHistory should record the old name');
R.updateSubject(s2, struct('Name','M002'));
fprintf('PASS: rename blocked while data exists, allowed and recorded otherwise\n');

% 6. Two rigs on one file --------------------------------------------------
% A adds X while B, which never reloaded, adds Y. Neither may be lost: B's
% write reloads first and so already contains X.
rigA = epsych.SubjectRoster(rosterFile);
rigB = epsych.SubjectRoster(rosterFile);
rigA.addSubject(struct('Name','RIG_A','Sex','Male','Species','Mouse'));
rigB.addSubject(struct('Name','RIG_B','Sex','Male','Species','Mouse'));

both = epsych.SubjectRoster(rosterFile);
assert(~isempty(both.findSubject('RIG_A')), 'Rig A''s subject was lost');
assert(~isempty(both.findSubject('RIG_B')), 'Rig B''s subject was lost');
assert(~isempty(rigB.findSubject('RIG_A')), 'Rig B should have picked up A''s subject');

residue = [dir(fullfile(root,'*.tmp')); dir(fullfile(root,'*.lock'))];
assert(isempty(residue), 'Temp or lock files were left behind: %s', ...
    strjoin({residue.name}, ', '));
fprintf('PASS: concurrent writes keep both records, leaving no .tmp or .lock\n');

% 7. A failed write must not damage the good file --------------------------
% Point a roster at a directory: saving must fail without throwing and without
% disturbing the real roster.
before = dir(rosterFile);
dirAsFile = fullfile(root, 'adirectory');
mkdir(dirAsFile);
unwritable = epsych.SubjectRoster(dirAsFile);
assert(~unwritable.save(), 'Saving onto a directory should report failure');
assert(~unwritable.IsWritable, 'A failed write should latch IsWritable false');
after = dir(rosterFile);
assert(after.bytes == before.bytes, 'The good roster file must be untouched');
fprintf('PASS: an unwritable target fails safely and latches IsWritable\n');

% 8. The BoxID seam --------------------------------------------------------
S = R.toSubject(s1, BoxID = 4);
assert(isa(S,'epsych.DefaultSubject') && S.BoxID == 4 && S.isValid(), ...
    'toSubject should produce a valid epsych.Subject');
assert(~isfield(R.Subjects(1), 'BoxID'), ...
    'Roster records must not carry a BoxID: a box belongs to a session');
backId = R.fromSubject(S);
assert(strcmp(backId, s1), 'fromSubject should match the existing record by name');
fprintf('PASS: BoxID is supplied at assignment, never stored on the roster\n');

% 9. Batch commit into a session ------------------------------------------
delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx = epsych.RunExpt;
cleanupRx = onCleanup(@() delete(findall(groot,'Type','figure','Tag','RunExpt')));

ids = {s1, s2, s3};
for i = 1:numel(ids)
    R.assign(ids{i}, p1);
    R.rememberProtocol(ids{i}, p1, proto);
end

report = R.assignToSession(rx, ids, ProjectID = p1);
assert(report.ok && numel(report.added) == 3, 'Three subjects should have been added');
assert(numel(rx.CONFIG) == 3, 'CONFIG should hold three entries');
assert(~isempty(rx.CONFIG(1).protocol_fn), 'Slot 1 must be reused, not left as a placeholder');
boxes = arrayfun(@(c) c.SUBJECT.BoxID, rx.CONFIG);
assert(numel(unique(boxes)) == 3, 'Box IDs must be unique');
assert(all(arrayfun(@(c) isa(c.SUBJECT,'epsych.Subject') && c.SUBJECT.isValid(), rx.CONFIG)), ...
    'Every committed subject must be a valid epsych.Subject');
assert(rx.STATE >= PRGMSTATE.CONFIGLOADED, 'The session should be ready after a commit');

st = epsych.SelfTest(rx);
results = st.run();
% Only the D group (config & subjects) is this feature's business. Other
% groups can legitimately fail on the test fixture -- E4 wants per-box trigger
% parameters that TEST_NEW_PROTOCOL2 only defines for box 1.
configChecks = results(startsWith([results.id], "D"));
failed = configChecks(strcmp([configChecks.status], "fail"));
% assert evaluates its message arguments eagerly, so the list is built first
% rather than inside the call, where an empty result would throw.
failedIds = strjoin(string({failed.id}), ', ');
assert(isempty(failed), 'SelfTest config checks failed: %s', failedIds);
fprintf('PASS: batch commit populates CONFIG and passes the D-group self-test\n');

% 10. All-or-nothing refusals ---------------------------------------------
delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx2 = epsych.RunExpt;

missingProto = R.assignToSession(rx2, {s1, s2}, ProjectID = p1, ...
    Protocols = {proto, fullfile(root,'does_not_exist.eprot')});
assert(missingProto.aborted && isempty(missingProto.added), ...
    'A missing protocol must abort the batch');
assert(isempty(rx2.CONFIG(1).protocol_fn), 'An aborted batch must leave CONFIG untouched');

manyIds = cell(1,17);
for i = 1:17
    manyIds{i} = R.addSubject(struct('Name',sprintf('BOX%02d',i),'Sex','Male','Species','Mouse'));
    R.assign(manyIds{i}, p1);
    R.rememberProtocol(manyIds{i}, p1, proto);
end
full = R.assignToSession(rx2, manyIds, ProjectID = p1);
assert(full.aborted && isempty(full.added), 'Box exhaustion must abort the batch');
assert(isempty(rx2.CONFIG(1).protocol_fn), 'An aborted batch must leave CONFIG untouched');
fprintf('PASS: a bad protocol and box exhaustion each refuse the whole batch\n');

% 11. Import from a config, twice -----------------------------------------
cfg = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'tmp', 'AversiveDetectionConfig.ecfg');
if isfile(cfg)
    fresh = fullfile(root, 'imported.esub');
    RI = epsych.SubjectRoster(fresh);
    pi_ = RI.addProject('Imported');
    r1 = RI.importFromConfig(cfg, ProjectID = pi_);
    assert(numel(r1.imported) >= 1, 'Import should have created at least one subject');
    n1 = numel(RI.Subjects);

    r2 = RI.importFromConfig(cfg, ProjectID = pi_);
    assert(isempty(r2.imported) && ~isempty(r2.linked), ...
        'A second import must link, not duplicate');
    assert(numel(RI.Subjects) == n1, 'A second import must not add records');
    assert(~isempty(RI.Subjects(1).ImportedFrom), 'Provenance should be recorded');
    fprintf('PASS: import links rather than duplicating on a second run\n');
else
    fprintf('SKIP: %s is missing; import not exercised\n', cfg);
end

% 12. Export ---------------------------------------------------------------
T = R.exportTable();
assert(istable(T) && height(T) > 0, 'exportTable should return a populated table');
assert(all(ismember({'Subject','Project','LastProtocol'}, T.Properties.VariableNames)), ...
    'exportTable is missing expected columns');
fprintf('PASS: exportTable flattens the roster for writetable\n');

% 13. A project owns the behavior GUI ------------------------------------------
% All three states, because each has a different failure mode: a named GUI must
% reach FUNCS.BehaviorGUI, 'none' must clear it, and empty must leave the session's
% own value alone rather than silently disabling the GUI.
delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx3 = epsych.RunExpt;

pg = R.addProject('BehaviorGUIStudy', DefaultProtocol = proto, BehaviorGUI = 'ep_GenericGUI');
assert(strcmp(epsych.SubjectRoster(rosterFile).findProject(pg).BehaviorGUI, 'ep_GenericGUI'), ...
    'A project''s BehaviorGUI did not survive a reload');

bg = cell(1,3);
for i = 1:3
    bg{i} = R.addSubject(struct('Name',sprintf('BG%02d',i),'Sex','Male','Species','Mouse'));
    R.assign(bg{i}, pg);
end

rep = R.assignToSession(rx3, bg(1), ProjectID = pg);
assert(rep.ok && strcmp(rx3.FUNCS.BehaviorGUI, 'ep_GenericGUI'), ...
    'A commit should apply the project''s behavior GUI to the session');

R.updateProject(pg, struct('BehaviorGUI', epsych.SubjectRoster.BEHAVIORGUI_NONE));
rep = R.assignToSession(rx3, bg(2), ProjectID = pg);
assert(rep.ok && isempty(rx3.FUNCS.BehaviorGUI), ...
    'A project set to BEHAVIORGUI_NONE should leave the session with no behavior GUI');

rx3.FUNCS.BehaviorGUI = 'ep_GenericGUI';
R.updateProject(pg, struct('BehaviorGUI',''));
rep = R.assignToSession(rx3, bg(3), ProjectID = pg);
assert(rep.ok && strcmp(rx3.FUNCS.BehaviorGUI, 'ep_GenericGUI'), ...
    'An empty BehaviorGUI must inherit the session default, not clear it');
fprintf('PASS: a project applies, disables, or inherits the session behavior GUI\n');

delete(findall(groot,'Type','figure','Tag','RunExpt'));

% 14. Project links --------------------------------------------------------
% The address is the part that matters: a roster is a shared file, so a link in
% it is untrusted input, and 'matlab:' would make an .esub executable.
[ok, ~, u] = epsych.SubjectRoster.isSafeUrl('docs.google.com/spreadsheets/d/1');
assert(ok && strcmp(u, 'https://docs.google.com/spreadsheets/d/1'), ...
    'A bare host should gain https://');
[ok, ~, u] = epsych.SubjectRoster.isSafeUrl('C:\lab\My Logs\notes.html');
assert(ok && strcmp(u, 'file:///C:/lab/My%20Logs/notes.html'), ...
    'A drive path should become a file URL with its spaces escaped (got %s)', u);
assert(epsych.SubjectRoster.isSafeUrl('\\nas\gap\logs'), 'A UNC path should be accepted');
for bad = {'matlab:!del /q c:\', 'javascript:alert(1)', 'data:text/html,x', 'not a url', ''}
    assert(~epsych.SubjectRoster.isSafeUrl(bad{1}), ...
        '"%s" must be refused as a link address', bad{1});
end
fprintf('PASS: only navigable addresses are accepted, and they are normalized\n');

L = [epsych.SubjectRoster.makeLink('Notebook','elog.lab.edu/gap'), ...
     epsych.SubjectRoster.makeLink('docs.google.com/spreadsheets/d/1')];
assert(strcmp(L(2).Label, 'docs.google.com'), ...
    'An unlabelled link should be named after its host (got "%s")', L(2).Label);

pl = R.addProject('LinkedStudy', Investigator = 'D. Stolzberg', ...
    IACUCProtocol = 'R-2026-11', Links = L, Archived = true);

q = epsych.SubjectRoster(rosterFile).findProject(pl);
assert(numel(q.Links) == 2 && strcmp(q.Links(1).URL, 'https://elog.lab.edu/gap'), ...
    'A project''s links did not survive a reload');
assert(strcmp(q.Investigator,'D. Stolzberg') && strcmp(q.IACUCProtocol,'R-2026-11'), ...
    'Investigator and IACUC protocol did not survive a reload');
assert(q.Archived, 'The archived flag did not survive a reload');

% Assigned, never passed to struct(): struct('Links', L) would build one
% project struct per link instead of one struct holding them all.
P = struct();
P.Links = struct('Label','Evil','URL','matlab:rmdir(''.'',''s'')');
try
    R.updateProject(pl, P);
    error('An unsafe link should have been refused');
catch ME
    assert(strcmp(ME.identifier, 'epsych:SubjectRoster:UnsafeLink'), ...
        'Wrong error for an unsafe link: %s', ME.identifier);
end
assert(numel(R.findProject(pl).Links) == 2, ...
    'A refused link must leave the stored links untouched');

P.Links = epsych.SubjectRoster.emptyLink();
R.updateProject(pl, P);
assert(isempty(epsych.SubjectRoster(rosterFile).findProject(pl).Links), ...
    'Clearing the links should persist as no links');
fprintf('PASS: project links, investigator, IACUC, and archived round trip\n');

% 15. A roster written before these fields existed --------------------------
% normalize_ fills a missing field from blankProject_ rather than migrating, so
% every new default has to mean what an older file implicitly meant. This is the
% assertion that fails if one of them does not.
legacyFile = fullfile(root, 'legacy.esub');
S = load(rosterFile, '-mat');
formatVersion = S.formatVersion;
subjects      = S.subjects;
memberships   = S.memberships;
meta          = S.meta;
projects      = rmfield(S.projects, ...
    {'Investigator','IACUCProtocol','Links','Archived', ...
     'SavingFcn','TimerPeriod','VideoRootDir','IntanRootDir','IntanSettingsFile'});
save(legacyFile, 'formatVersion', 'subjects', 'projects', 'memberships', 'meta', '-mat');

Rold = epsych.SubjectRoster(legacyFile);
assert(isempty(Rold.LoadError) && Rold.IsWritable, ...
    'An older roster must open normally: %s', Rold.LoadError);
assert(numel(Rold.Projects) == numel(S.projects), 'An older roster lost projects');
assert(~any([Rold.Projects.Archived]), 'A project from an older file must not read as archived');
assert(all(cellfun(@isempty, {Rold.Projects.Investigator})), 'Investigator should default to empty');
assert(all(cellfun(@isempty, {Rold.Projects.Links})), 'Links should default to none');
% The session defaults have to default to "inherit", or opening an old roster
% would start rewriting the rig's saving function and timer period.
assert(all(isnan([Rold.Projects.TimerPeriod])), 'TimerPeriod should default to NaN (inherit)');
assert(all(cellfun(@isempty, {Rold.Projects.SavingFcn})), 'SavingFcn should default to empty');
assert(all(cellfun(@isempty, {Rold.Projects.VideoRootDir})), 'VideoRootDir should default to empty');
oldId = Rold.Projects(1).ProjectID;
Rold.updateProject(oldId, struct('Notes','still writable'));
assert(strcmp(epsych.SubjectRoster(legacyFile).findProject(oldId).Notes, 'still writable'), ...
    'An older roster must stay writable once the new fields are filled in');
fprintf('PASS: a roster written before these options loads, defaults, and still writes\n');

% 14. Protocol versions: check, update, revert -----------------------------
% The whole point of recording a version is to notice an .eprot that was saved
% over since a subject last ran it, so the fixture is copied and re-saved
% rather than edited: epsych.Protocol.save is what bumps vN.
protoA = fullfile(root, 'phase_a.eprot');
protoB = fullfile(root, 'phase_b.eprot');
copyfile(proto, protoA);
PA = epsych.Protocol.load(protoA);
PA.save(protoA);
vA1 = epsych.Protocol.versionOnDisk(protoA);
PA.save(protoB);
vB = epsych.Protocol.versionOnDisk(protoB);
assert(~isempty(vA1) && ~isempty(vB), 'The fixtures should carry protocol versions');
assert(epsych.Protocol.versionNumber(vB) > epsych.Protocol.versionNumber(vA1), ...
    'Each save must increment the comparable part of the version');

pv = R.addProject('VersionStudy', DefaultProtocol = protoA);
sv = R.addSubject(struct('Name','V001','Sex','Male','Species','Mouse'));
R.assign(sv, pv);

st = R.protocolStatus(sv, pv);
assert(strcmp(st.Status,'unknown') && strcmp(st.Protocol, protoA), ...
    'A subject that has never run resolves to the default with no version recorded');

R.rememberProtocol(sv, pv, protoA);
st = R.protocolStatus(sv, pv);
assert(strcmp(st.Status,'current') && strcmp(st.Version, vA1), ...
    'A freshly recorded protocol should read as current');

% The operator edits and saves the protocol the subject is on.
PA.save(protoA);
vA2 = epsych.Protocol.versionOnDisk(protoA);
st = R.protocolStatus(sv, pv);
assert(st.IsOutdated && strcmp(st.Status,'outdated') && strcmp(st.LatestVersion, vA2), ...
    'Saving the protocol must leave the subject behind the file');

rep = R.updateProtocol({sv}, pv);
assert(rep.ok && numel(rep.updated) == 1 && strcmp(rep.updated(1).ToVersion, vA2), ...
    'updateProtocol should bring the subject onto the version in the file');
st = R.protocolStatus(sv, pv);
assert(strcmp(st.Status,'current'), 'The subject should read as current after an update');

reloaded = epsych.SubjectRoster(rosterFile);
stR = reloaded.protocolStatus(sv, pv);
assert(strcmp(stR.Version, vA2), 'The recorded version must survive a reload');

again = R.updateProtocol({sv}, pv);
assert(~again.ok && numel(again.skipped) == 1, ...
    'Updating an already-current subject should change nothing');

% Same file, earlier version: the entry is on record but the file has moved on,
% so a revert to it can restore the pointer and not the content.
h = R.protocolHistory(sv, pv);
assert(~isempty(h) && strcmp(h(1).File, protoA) && strcmp(h(1).Version, vA1), ...
    'The superseded version should be on the history');
assert(~h(1).Recoverable, ...
    'An .eprot saved over cannot be recovered, and must not claim otherwise');

% Different file: reverting between revisions kept as separate files IS exact.
R.updateProtocol({sv}, pv, Protocol = protoB);
st = R.protocolStatus(sv, pv);
assert(strcmp(st.Status,'differs') && strcmp(st.Protocol, protoB), ...
    'A subject off the project default should be reported as differing');

h = R.protocolHistory(sv, pv);
assert(strcmp(h(1).File, protoA) && strcmp(h(1).Version, vA2) && h(1).Recoverable, ...
    'The protocol just left should head the history, and be exactly recoverable');

rev = R.revertProtocol(sv, pv);
assert(rev.ok && rev.Recoverable, 'Reverting to an unchanged file should be exact');
st = R.protocolStatus(sv, pv);
assert(strcmp(st.Protocol, protoA) && strcmp(st.Version, vA2) && strcmp(st.Status,'current'), ...
    'Revert should put the subject back on the earlier protocol');

h = R.protocolHistory(sv, pv);
assert(strcmp(h(1).File, protoB), 'Reverting must itself be undoable');
assert(~any(strcmp({h.File}, protoA) & strcmp({h.Version}, vA2)), ...
    'The restored entry must leave the history, not sit in it twice');

noHistory = R.addSubject(struct('Name','V002','Sex','Male','Species','Mouse'));
R.assign(noHistory, pv);
nothing = R.revertProtocol(noHistory, pv);
assert(~nothing.ok, 'A subject with no history has nothing to revert to');

% All Subjects has no project context, so there is no membership to write.
noProject = R.updateProtocol({sv}, '');
assert(~noProject.ok, 'updateProtocol must refuse without a project');
fprintf('PASS: protocol versions are recorded, checked, updated, and reverted\n');

% 16. A project owns the session settings ----------------------------------
% These moved off the rig (RunExpt's Customize dialog) and onto the study, so
% the assertions that matter are that a project's values reach the session, and
% that a project which names none leaves the session exactly as it found it.
delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx4 = epsych.RunExpt;

studyRoot = fullfile(root, 'studydata');
videoRoot = fullfile(root, 'video');
intanRoot = fullfile(root, 'intan');
mkdir(studyRoot); mkdir(videoRoot); mkdir(intanRoot);

% A distinguishable starting point on the session side.
rx4.DefaultDataPath = string(root);
rx4.FUNCS.SavingFcn = 'ep_TimerFcn_Start';   % any resolvable name that is not the project's
rx4.FUNCS.TimerPeriod = 0.01;
rx4.PATHS = struct('VideoRootDir','','IntanRootDir','','IntanSettingsFile','');

pd = R.addProject('DefaultsStudy', DefaultProtocol = proto, ...
    DefaultDataPath = studyRoot, SavingFcn = 'ep_SaveDataFcn', ...
    TimerPeriod = 0.05, VideoRootDir = videoRoot, IntanRootDir = intanRoot, ...
    IntanSettingsFile = fullfile(root, 'rhx.xml'));

pdReloaded = epsych.SubjectRoster(rosterFile).findProject(pd);
assert(strcmp(pdReloaded.SavingFcn,'ep_SaveDataFcn') && pdReloaded.TimerPeriod == 0.05 && ...
    strcmp(pdReloaded.VideoRootDir, videoRoot), ...
    'The session defaults did not survive a reload');

sd = R.addSubject(struct('Name','SD01','Sex','Male','Species','Mouse'));
R.assign(sd, pd);
rep = R.assignToSession(rx4, {sd}, ProjectID = pd);
assert(rep.ok, 'The commit should have succeeded: %s', rep.message);
assert(strcmp(char(rx4.DefaultDataPath), studyRoot), 'The project data path should reach the session');
assert(strcmp(rx4.FUNCS.SavingFcn, 'ep_SaveDataFcn'), 'The project saving function should reach the session');
assert(rx4.FUNCS.TimerPeriod == 0.05, 'The project timer period should reach the session');
assert(strcmp(rx4.PATHS.VideoRootDir, videoRoot), 'The project video path should reach the session');
assert(strcmp(rx4.PATHS.IntanRootDir, intanRoot), 'The project Intan path should reach the session');
assert(strcmp(rx4.PATHS.IntanSettingsFile, fullfile(root,'rhx.xml')), ...
    'The project Intan settings file should reach the session');
% The machine's own preferences must be untouched: one study's paths are not
% the rig's, and the next session without a project has to get them back.
assert(~ispref('ep_RunExpt_Video','RecordingRootDir') || ...
    ~strcmp(char(getpref('ep_RunExpt_Video','RecordingRootDir')), videoRoot), ...
    'Applying a project must not rewrite the machine preferences');

% A project that names nothing inherits, rather than blanking the session.
pn = R.addProject('InheritStudy', DefaultProtocol = proto);
sn = R.addSubject(struct('Name','SD02','Sex','Male','Species','Mouse'));
R.assign(sn, pn);
before = {char(rx4.DefaultDataPath), rx4.FUNCS.SavingFcn, rx4.FUNCS.TimerPeriod, rx4.PATHS};
rep = R.assignToSession(rx4, {sn}, ProjectID = pn);
assert(rep.ok, 'The inherit commit should have succeeded: %s', rep.message);
assert(isequal(before, {char(rx4.DefaultDataPath), rx4.FUNCS.SavingFcn, rx4.FUNCS.TimerPeriod, rx4.PATHS}), ...
    'A project with no session defaults must leave the session alone');

% A period the timer cannot run is refused on the way in, not at run start.
for badPeriod = [0, 5]
    threw = false;
    try
        R.addProject(sprintf('BadPeriod%g', badPeriod), TimerPeriod = badPeriod);
    catch ME
        threw = strcmp(ME.identifier, 'epsych:SubjectRoster:InvalidTimerPeriod');
    end
    assert(threw, 'A timer period of %g must be refused', badPeriod);
end
threw = false;
try
    R.updateProject(pd, struct('TimerPeriod', 42));
catch ME
    threw = strcmp(ME.identifier, 'epsych:SubjectRoster:InvalidTimerPeriod');
end
assert(threw, 'updateProject must refuse an unusable timer period');
assert(R.findProject(pd).TimerPeriod == 0.05, 'A refused period must leave the record alone');

R.updateProject(pd, struct('SavingFcn','ep_TimerFcn_Stop', 'TimerPeriod', 0.02));
q = epsych.SubjectRoster(rosterFile).findProject(pd);
assert(strcmp(q.SavingFcn,'ep_TimerFcn_Stop') && q.TimerPeriod == 0.02, ...
    'updateProject should write both the text and numeric session defaults');
fprintf('PASS: a project applies, or inherits, the session settings\n');

delete(findall(groot,'Type','figure','Tag','RunExpt'));

% 17. Copying a project ----------------------------------------------------
% The settings are the reason to copy; the subjects are a separate question,
% and the answer must not be assumed either way.
srcName = 'CopySource';
srcLinks = epsych.SubjectRoster.makeLink('Notebook','elog.lab.edu/copy');
pc = R.addProject(srcName, Notes = 'phase one', Investigator = 'D. Stolzberg', ...
    IACUCProtocol = 'R-2026-12', DefaultProtocol = proto, ...
    DefaultDataPath = root, SavingFcn = 'ep_SaveDataFcn', TimerPeriod = 0.02, ...
    VideoRootDir = root, IntanRootDir = root, BehaviorGUI = 'ep_GenericGUI', ...
    Links = srcLinks, Archived = true);

cs = cell(1,3);
for i = 1:3
    cs{i} = R.addSubject(struct('Name',sprintf('CP%02d',i),'Sex','Female','Species','Mouse'));
    R.assign(cs{i}, pc);
end
R.rememberProtocol(cs{1}, pc, proto, 4);
R.setActive(cs{3}, pc, false);   % retired, and so left behind by default

% Settings only -- and every one of them, read back off disk.
pEmpty = R.copyProject(pc, 'CopyEmpty');
q = epsych.SubjectRoster(rosterFile).findProject(pEmpty);
for f = {'Notes','Investigator','IACUCProtocol','DefaultProtocol', ...
         'DefaultDataPath','SavingFcn','VideoRootDir','IntanRootDir','BehaviorGUI'}
    assert(strcmp(q.(f{1}), R.findProject(pc).(f{1})), ...
        'A copy did not inherit %s', f{1});
end
assert(q.TimerPeriod == 0.02, 'A copy did not inherit the timer period');
assert(isscalar(q.Links) && strcmp(q.Links.URL, 'https://elog.lab.edu/copy'), ...
    'A copy did not inherit the project links');
assert(~q.Archived, 'A copy must not inherit Archived; it would open hidden');
assert(isempty(R.subjectsInProject(pEmpty, IncludeRetired = true)), ...
    'A settings-only copy must enroll nobody');
assert(numel(R.subjectsInProject(pc, IncludeRetired = true)) == 3, ...
    'Copying must not disturb the source''s members');

% With subjects: the active two, still in the source, carrying what they ran.
pFull = R.copyProject(pc, 'CopyFull', IncludeSubjects = true, ...
    DefaultProtocol = '', Archived = true);
moved = R.subjectsInProject(pFull);
assert(numel(moved) == 2, 'Only the two active members should have come along (got %d)', numel(moved));
assert(~ismember('CP03', {moved.Name}), 'A retired member must be left behind by default');
assert(strcmp(R.lastProtocol(cs{1}, pFull), proto), ...
    'A copied membership should keep the protocol it was on');
assert(isempty(R.protocolHistory(cs{1}, pFull)), ...
    'A membership created by a copy has no change to undo, so no history');
assert(isempty(R.findProject(pFull).DefaultProtocol), 'An override must beat the source');
assert(R.findProject(pFull).Archived, 'Archived must be honoured when stated');
assert(numel(R.projectsForSubject(cs{1})) >= 2, ...
    'A copied subject must be in both projects, not moved out of the source');

% Retired members and a cohort with no protocol memory, each on request.
pAll = R.copyProject(pc, 'CopyAll', IncludeSubjects = true, ...
    IncludeRetired = true, CopyProtocolMemory = false);
assert(numel(R.subjectsInProject(pAll, IncludeRetired = true)) == 3, ...
    'IncludeRetired should bring all three');
assert(numel(R.subjectsInProject(pAll)) == 2, 'A retired member must arrive retired');
assert(isempty(R.findMembership(cs{1}, pAll).LastProtocol), ...
    'CopyProtocolMemory=false should leave the membership with no protocol');
assert(strcmp(R.lastProtocol(cs{1}, pAll), proto), ...
    'and the project default should then be what it falls back to');

threw = false;
try
    R.copyProject(pc, srcName);
catch ME
    threw = strcmp(ME.identifier, 'epsych:SubjectRoster:DuplicateName');
end
assert(threw, 'A copy must be refused the name of an existing project');

threw = false;
try
    R.copyProject('NoSuchProjectAtAll', 'Whatever');
catch ME
    threw = strcmp(ME.identifier, 'epsych:SubjectRoster:NoSuchProject');
end
assert(threw, 'Copying a project that does not exist must say so');
fprintf('PASS: a project copies its settings, and its subjects only when asked\n');

% 18. Replacing the session subject list ------------------------------------
% What the manager's "Add Checked to Session" button asks for: the batch IS the
% session's subject list, so yesterday's animal cannot be left behind in a box.
delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx5 = epsych.RunExpt;
cleanupRx5 = onCleanup(@() delete(findall(groot,'Type','figure','Tag','RunExpt')));

rep = R.assignToSession(rx5, {s1, s2}, ProjectID = p1);
assert(rep.ok && numel(rx5.CONFIG) == 2, 'Two subjects should be in the session to displace');
assert(isempty(rep.removed), 'An appending commit must remove nobody');
firstBoxes = arrayfun(@(c) c.SUBJECT.BoxID, rx5.CONFIG);

rep = R.assignToSession(rx5, {s3}, ProjectID = p1, ReplaceExisting = true);
assert(rep.ok && isscalar(rx5.CONFIG), ...
    'A replacing commit should leave only the checked subject (got %d)', numel(rx5.CONFIG));
assert(strcmp(rx5.CONFIG(1).SUBJECT.Name, 'M003'), 'The wrong subject survived the replacement');
assert(numel(rep.removed) == 2 && all(ismember({'M001','M002'}, rep.removed)), ...
    'The report must name both displaced subjects');
assert(rx5.CONFIG(1).SUBJECT.BoxID == firstBoxes(1), ...
    'A box the outgoing subject held must be free to the batch');
assert(rx5.STATE >= PRGMSTATE.CONFIGLOADED, 'The session should still be ready after a replacement');

% The same animal, re-added in the box it already occupies: with the old list
% treated as occupied this would skip as "already in the session" and commit
% nothing.
rep = R.assignToSession(rx5, {s3}, ProjectID = p1, ...
    BoxIDs = rx5.CONFIG(1).SUBJECT.BoxID, ReplaceExisting = true);
assert(rep.ok && isscalar(rx5.CONFIG) && isempty(rep.skipped), ...
    'Re-adding the same subject in the same box must commit: %s', rep.message);

% A refused batch must not cost the operator the list they had.
rep = R.assignToSession(rx5, {s1, s2}, ProjectID = p1, ReplaceExisting = true, ...
    Protocols = {proto, fullfile(root,'still_not_there.eprot')});
assert(rep.aborted && isempty(rep.removed), 'A missing protocol must abort before anything is removed');
assert(isscalar(rx5.CONFIG) && strcmp(rx5.CONFIG(1).SUBJECT.Name,'M003'), ...
    'An aborted replacement must leave the session exactly as it was');
fprintf('PASS: a replacing commit swaps the subject list, and an aborted one leaves it alone\n');

clear cleanupRx5
delete(findall(groot,'Type','figure','Tag','RunExpt'));

% N. No default location ---------------------------------------------------
% The roster used to fall back to <prefdir>/epsych/subjects.esub, which meant a
% lab's only copy of its animal records lived somewhere nobody chose and a
% MATLAB upgrade lost. There is no fallback now: unconfigured is a real state,
% it reads as empty, and it refuses to be written rather than inventing a path.
epsych.SubjectRoster.setConfiguredFile('');
assert(isempty(epsych.SubjectRoster.configuredFile()), ...
    'Clearing the preference must leave no path at all, not a fallback');
assert(~epsych.SubjectRoster.isConfigured(), 'isConfigured must be false with no preference');

U = epsych.SubjectRoster();
assert(~U.IsBound, 'A roster built with no configured file must be unbound');
assert(isempty(U.Subjects) && isempty(U.Projects), 'An unbound roster must read as empty');
assert(~U.IsWritable, 'An unbound roster must not claim to be writable');
% Not a LoadError: nothing failed, the question has simply not been answered.
assert(isempty(U.LoadError), 'Unconfigured is not a read failure');

% Throws rather than failing quietly: addProject mints an ID and reports
% success without checking mutate_'s return, so a silent refusal would look
% exactly like a project that was saved.
threw = false;
try
    U.addProject('Nowhere');
catch ME
    threw = strcmp(ME.identifier, 'epsych:SubjectRoster:NoFile');
end
assert(threw, 'An unbound roster must refuse to add a project, loudly');
assert(isempty(U.Projects), 'The refused project must not linger in memory');
fprintf('PASS: with no file chosen the roster is empty, read-only, and refuses to write\n');

% N+1. setConfiguredFile validates at the point of choosing ----------------
threw = false;
try
    epsych.SubjectRoster.setConfiguredFile(root);
catch ME
    threw = strcmp(ME.identifier, 'epsych:SubjectRoster:PathIsFolder');
end
assert(threw, 'A folder must be refused: movefile onto one saves nothing and reports success');

deepFile = fullfile(root, 'made', 'up', 'lab_roster');
rep = epsych.SubjectRoster.setConfiguredFile(deepFile);
assert(strcmp(rep.FilePath, [deepFile '.esub']), ...
    'A path with no extension should gain %s, got %s', ...
    epsych.SubjectRoster.FILE_EXTENSION, rep.FilePath);
assert(isfolder(fullfile(root, 'made', 'up')), ...
    'The folder should be created when the roster is chosen, not at the first save');
assert(~rep.Existed && ~rep.Migrated, 'A fresh path should report neither existing nor migrated');
assert(strcmp(epsych.SubjectRoster().FilePath, rep.FilePath), ...
    'The default constructor should open the file just configured');
fprintf('PASS: choosing a roster validates the path and makes its folder\n');

% N+2. The legacy per-user roster is adopted once ---------------------------
% Read-only with respect to the operator's own data: the old file is copied,
% never moved, and this only ever reads it. Skipped on a machine that never
% had one.
legacy = epsych.SubjectRoster.legacyFile();
if isempty(legacy)
    fprintf('SKIP: no legacy per-user roster on this machine to adopt\n');
else
    before = epsych.SubjectRoster(legacy);

    epsych.SubjectRoster.setConfiguredFile('');
    adopted = fullfile(root, 'adopted.esub');
    rep = epsych.SubjectRoster.setConfiguredFile(adopted, AdoptLegacy = true);
    assert(rep.Migrated && strcmp(rep.MigratedFrom, legacy), ...
        'The first file chosen should adopt the legacy roster');
    assert(isfile(legacy), 'Adoption must copy, never move: the original stays put');
    assert(numel(epsych.SubjectRoster(adopted).Subjects) == numel(before.Subjects), ...
        'The adopted roster should hold what the legacy one held');

    % Only ever on the FIRST choice. Re-pointing a configured rig at a new
    % empty file is a deliberate fresh start, and filling it with records from
    % a file the operator has stopped using would be the opposite of that.
    again = fullfile(root, 'second_choice.esub');
    rep2 = epsych.SubjectRoster.setConfiguredFile(again, AdoptLegacy = true);
    assert(~rep2.Migrated, 'A rig that already has a roster must not adopt the legacy one');
    assert(~isfile(again), 'A second choice should stay empty until something is saved');
    fprintf('PASS: the legacy per-user roster is adopted once, by copy, on the first choice\n');
end

% Off by default, so a script or a test that names a fresh roster gets one.
epsych.SubjectRoster.setConfiguredFile('');
plain = fullfile(root, 'plain.esub');
rep = epsych.SubjectRoster.setConfiguredFile(plain);
assert(~rep.Migrated && ~isfile(plain), ...
    'Adoption must be opt-in; a scripted choice should gain nothing it did not ask for');
fprintf('PASS: adoption is opt-in\n');

fprintf('\nALL SUBJECT ROSTER SMOKE TESTS PASSED\n');

end

% -----------------------------------------------------------------------
function localRestoreAll(savedSubjectPrefs, savedRunExptPrefs)
localRestorePrefs('ep_RunExpt_Subjects', savedSubjectPrefs);
localRestorePrefs('RunExpt', savedRunExptPrefs);
end

% -----------------------------------------------------------------------
function saved = localSavePrefs(group)
% Snapshot a preference group so the test can put it back.
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

% -----------------------------------------------------------------------
function saved = localDropTempRoster(saved)
% Drop a RosterFile that points into tempdir from a preference snapshot.
if ~saved.existed || ~isfield(saved.values, 'RosterFile'), return, end

p = char(string(saved.values.RosterFile));
if startsWith(lower(p), lower(tempdir))
    fprintf('NOTE: dropping a stale test roster path from the preferences: %s\n', p);
    saved.values = rmfield(saved.values, 'RosterFile');
end
end

% -----------------------------------------------------------------------
function localRestorePrefs(group, saved)
if ispref(group)
    rmpref(group);
end
if ~saved.existed, return, end
names = fieldnames(saved.values);
for i = 1:numel(names)
    setpref(group, names{i}, saved.values.(names{i}));
end
end

% -----------------------------------------------------------------------
function localRemoveDir(root)
if isfolder(root)
    try
        rmdir(root, 's');
    catch ME
        vprintf(2, ME);
    end
end
end
