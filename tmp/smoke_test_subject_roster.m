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

% 13. A project owns the box GUI ------------------------------------------
% All three states, because each has a different failure mode: a named GUI must
% reach FUNCS.BoxFig, 'none' must clear it, and empty must leave the session's
% own value alone rather than silently disabling the GUI.
delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx3 = epsych.RunExpt;

pg = R.addProject('BoxGuiStudy', DefaultProtocol = proto, BoxGUI = 'ep_GenericGUI');
assert(strcmp(epsych.SubjectRoster(rosterFile).findProject(pg).BoxGUI, 'ep_GenericGUI'), ...
    'A project''s BoxGUI did not survive a reload');

bg = cell(1,3);
for i = 1:3
    bg{i} = R.addSubject(struct('Name',sprintf('BG%02d',i),'Sex','Male','Species','Mouse'));
    R.assign(bg{i}, pg);
end

rep = R.assignToSession(rx3, bg(1), ProjectID = pg);
assert(rep.ok && strcmp(rx3.FUNCS.BoxFig, 'ep_GenericGUI'), ...
    'A commit should apply the project''s box GUI to the session');

R.updateProject(pg, struct('BoxGUI', epsych.SubjectRoster.BOXGUI_NONE));
rep = R.assignToSession(rx3, bg(2), ProjectID = pg);
assert(rep.ok && isempty(rx3.FUNCS.BoxFig), ...
    'A project set to BOXGUI_NONE should leave the session with no box GUI');

rx3.FUNCS.BoxFig = 'ep_GenericGUI';
R.updateProject(pg, struct('BoxGUI',''));
rep = R.assignToSession(rx3, bg(3), ProjectID = pg);
assert(rep.ok && strcmp(rx3.FUNCS.BoxFig, 'ep_GenericGUI'), ...
    'An empty BoxGUI must inherit the session default, not clear it');
fprintf('PASS: a project applies, disables, or inherits the session box GUI\n');

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
    {'Investigator','IACUCProtocol','Links','Archived'});
save(legacyFile, 'formatVersion', 'subjects', 'projects', 'memberships', 'meta', '-mat');

Rold = epsych.SubjectRoster(legacyFile);
assert(isempty(Rold.LoadError) && Rold.IsWritable, ...
    'An older roster must open normally: %s', Rold.LoadError);
assert(numel(Rold.Projects) == numel(S.projects), 'An older roster lost projects');
assert(~any([Rold.Projects.Archived]), 'A project from an older file must not read as archived');
assert(all(cellfun(@isempty, {Rold.Projects.Investigator})), 'Investigator should default to empty');
assert(all(cellfun(@isempty, {Rold.Projects.Links})), 'Links should default to none');
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
