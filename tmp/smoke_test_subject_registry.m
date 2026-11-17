function smoke_test_subject_registry()
% smoke_test_subject_registry()
% The subject-registry seam, headless and with no registry code on the path:
% the "none" registry changes nothing and creates no preference; SessionUID is
% a v4 UUID that leaves the global random stream alone; RegistryID round
% trips, refuses duplicates, and reads as "not linked" in an old file;
% importSubjects links, adds, updates, skips, and enrols without reviving a
% retired member; weighings and sessions reach an injected registry; and a
% registry that throws costs neither a roster write nor a session record.
%
%   matlab -batch "cd('tmp'); smoke_test_subject_registry"
%
% See also: epsych.SubjectRegistry, epsych.SessionRecord, FakeSubjectRegistry

epsych_startup

savedSubjectPrefs = localSavePrefs('ep_RunExpt_Subjects');
savedEPsychPrefs  = localSavePrefs('EPsych');
cleanupPrefs = onCleanup(@() localRestoreAll(savedSubjectPrefs, savedEPsychPrefs));
cleanupReg = onCleanup(@() epsych.SubjectRegistry.current(Reset=true));

root = fullfile(tempdir, 'epsych_registry_smoke');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

% 1. The "none" registry ---------------------------------------------------
if ispref('EPsych', 'SubjectRegistry'), rmpref('EPsych', 'SubjectRegistry'); end
r = epsych.SubjectRegistry.current(Reset=true);
assert(isa(r, 'epsych.SubjectRegistry') && ~r.isEnabled(), 'With no preference the registry must be "none"');
st = r.status();
assert(st.State == "off" && st.Pending == 0, 'The "none" registry reports off');
T = r.subjectStatus(["A" "B"]);
assert(height(T) == 2 && ~any(T.Known) && all(isnan(T.WeightG)), 'subjectStatus answers one empty row per id');
W = r.sessionWarnings(struct('Name', {'A'}, 'RegistryID', {'A'}));
assert(isempty(W), 'The "none" registry never warns');
epsych.SubjectRegistry.notifySessionRunning(true);
epsych.SubjectRegistry.notifyWeight(struct('Name', 'A', 'RegistryID', '', 'SubjectID', 'S1'), 50, datetime('now'));
assert(~ispref('EPsych', 'SubjectRegistry'), 'Asking for the registry must not create its preference');
A = epsych.SubjectRegistry.availableAdapters();
assert(isstruct(A), 'availableAdapters returns a struct array even when none is present');
setpref('EPsych', 'SubjectRegistry', 'no.such.Adapter');
r = epsych.SubjectRegistry.current();
assert(~r.isEnabled(), 'A missing adapter class falls back to "none"');
rmpref('EPsych', 'SubjectRegistry');
epsych.SubjectRegistry.current(Reset=true);
fprintf('PASS: the "none" registry is inert and creates no preference\n');

% 2. SessionUID ------------------------------------------------------------
rng(12345, 'twister');
before = rng;
u = strings(1, 200);
for k = 1:numel(u)
    u(k) = epsych.newUUID();
end
after = rng;
assert(isequal(before.State, after.State), 'Minting a UUID must not touch the global random stream');
assert(numel(unique(u)) == numel(u), 'UUIDs must be unique');
assert(all(~cellfun(@isempty, regexp(cellstr(u), ...
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', 'once'))), ...
    'UUIDs must be lower-case RFC 4122 version 4');
info = epsych.SessionSnapshot.fromInfo(struct('FormatVersion', 1, 'DataFilename', 'x'), Quiet=true);
assert(isfield(info, 'SessionUID') && isempty(info.SessionUID), 'An older snapshot reads as no SessionUID');
fprintf('PASS: SessionUID is a v4 UUID and leaves rng alone\n');

% 3. RegistryID on the roster ---------------------------------------------
rosterFile = fullfile(root, 'subjects.esub');
R = epsych.SubjectRoster(rosterFile);
p1 = R.addProject('Detection', RegistryID = 'proj-uuid-1');
s1 = R.addSubject(struct('Name', 'G001', 'RegistryID', 'SUBJ-ID-1'));
s2 = R.addSubject(struct('Name', 'G002'));
assert(strcmp(R.findSubject(s1).RegistryID, 'SUBJ-ID-1'), 'addSubject keeps a RegistryID');
assert(isempty(R.findSubject(s2).RegistryID), 'A subject is unlinked by default');
assert(strcmp(R.findByRegistryID('SUBJ-ID-1').SubjectID, s1), 'findByRegistryID finds the linked subject');
assert(isempty(R.findByRegistryID('SUBJ-ID-404')), 'findByRegistryID finds nothing for an unknown id');
assert(isempty(R.findSubject('SUBJ-ID-1')), 'findSubject does not resolve registry ids');
localExpectError(@() R.addSubject(struct('Name', 'G003', 'RegistryID', 'SUBJ-ID-1')), ...
    'epsych:SubjectRoster:DuplicateRegistryID');
localExpectError(@() R.updateSubject(s2, struct('RegistryID', 'SUBJ-ID-1')), ...
    'epsych:SubjectRoster:DuplicateRegistryID');
R.updateSubject(s2, struct('RegistryID', ' SUBJ-ID-2 '));
assert(strcmp(R.findSubject(s2).RegistryID, 'SUBJ-ID-2'), 'updateSubject links (trimmed)');
R.updateSubject(s1, struct('RegistryID', 'SUBJ-ID-1'));   % keeping its own link is fine
R2 = epsych.SubjectRoster(rosterFile);
assert(strcmp(R2.findSubject(s2).RegistryID, 'SUBJ-ID-2'), 'RegistryID round trips through the file');
assert(strcmp(R2.findProject(p1).RegistryID, 'proj-uuid-1'), 'A project RegistryID round trips');
R.updateProject(p1, struct('RegistryID', 'proj-uuid-2'));
assert(strcmp(R.findProject(p1).RegistryID, 'proj-uuid-2'), 'updateProject changes a project RegistryID');
pc = R.copyProject(p1, 'Detection phase 2');
assert(strcmp(R.findProject(pc).RegistryID, 'proj-uuid-2'), 'copyProject carries the project link');
Tx = R.exportTable();
assert(ismember('RegistryID', Tx.Properties.VariableNames), 'exportTable has a RegistryID column');

% An older file: strip the field and reload.
oldFile = fullfile(root, 'old.esub');
copyfile(rosterFile, oldFile);
M = load(oldFile, '-mat');
M.subjects = rmfield(M.subjects, 'RegistryID');
M.projects = rmfield(M.projects, 'RegistryID');
save(oldFile, '-struct', 'M', '-mat');
Ro = epsych.SubjectRoster(oldFile);
assert(Ro.IsWritable && all(cellfun(@isempty, {Ro.Subjects.RegistryID})) && ...
    all(cellfun(@isempty, {Ro.Projects.RegistryID})), 'A roster written before RegistryID reads as unlinked');
fprintf('PASS: RegistryID round trips, is unique, and is blank in older files\n');

% 4. importSubjects --------------------------------------------------------
R.addSubject(struct('Name', 'SUBJ-ID-7'));                       % unlinked, same name
R.addSubject(struct('Name', 'SUBJ-ID-8', 'RegistryID', 'OTHER'));% linked elsewhere
sRet = R.addSubject(struct('Name', 'SUBJ-ID-9', 'RegistryID', 'SUBJ-ID-9'));
R.assign(sRet, p1);
R.setActive(sRet, p1, false);
recs = struct( ...
    'RegistryID', {'SUBJ-ID-5', 'SUBJ-ID-7', 'SUBJ-ID-8', 'SUBJ-ID-1', 'BAD:ID', 'SUBJ-ID-9', ''}, ...
    'Sex',        {'Female',    'Male',      'Male',      'Female',    'Male',   'Female',    'Male'}, ...
    'Species',    {'Gerbil',    'Gerbil',    'Gerbil',    'Gerbil',    'Gerbil', 'Gerbil',    'Gerbil'});
rep = R.importSubjects(recs, ProjectID = p1);
acts = [rep.Action];
assert(isequal(acts, ["added" "linked" "skipped" "updated" "skipped" "updated" "skipped"]), ...
    'importSubjects actions were %s', strjoin(acts, ','));
assert(contains(rep(3).Reason, 'OTHER'), 'A name linked elsewhere is skipped with the reason');
assert(contains(rep(7).Reason, 'no registry id'), 'A record without an id is skipped');
added = R.findByRegistryID('SUBJ-ID-5');
assert(strcmp(added.Name, 'SUBJ-ID-5') && strcmp(added.Sex, 'Female'), 'An added subject is named after its id');
assert(strcmp(R.findSubject('SUBJ-ID-7').RegistryID, 'SUBJ-ID-7'), 'A same-named unlinked subject is linked');
assert(strcmp(R.findSubject(s1).Sex, 'Female'), 'Identity is brought up to date on a linked subject');
assert(rep(1).Enrolled && rep(2).Enrolled && rep(4).Enrolled, 'Imported subjects are enrolled');
m = R.findMembership(sRet, p1);
assert(~m.Active && ~rep(6).Enrolled, 'A retired member stays retired');
mNew = R.findMembership(added.SubjectID, p1);
assert(~isempty(mNew) && mNew.Active, 'A new member is active');
rep2 = R.importSubjects(recs(1:2), ProjectID = p1);
assert(all([rep2.Action] == "unchanged") && ~any([rep2.Enrolled]), 'A second import changes nothing');
fprintf('PASS: importSubjects adds, links, updates, skips, and enrols\n');

% 5. Weighings reach the registry; a broken one costs nothing --------------
F = FakeSubjectRegistry();
epsych.SubjectRegistry.current(Use = F);
sw = R.addSubject(struct('Name', 'G010', 'RegistryID', 'SUBJ-ID-10', 'Weight', 70));
assert(numel(F.Weights) == 1 && F.Weights(1).Grams == 70 && F.Weights(1).RegistryID == "SUBJ-ID-10", ...
    'A new subject''s weight is a weighing');
R.updateSubject(sw, struct('Weight', 70, 'Notes', 'same weight'));
assert(numel(F.Weights) == 1, 'An unchanged weight is not a weighing');
R.updateSubject(sw, struct('Weight', 68.5));
assert(numel(F.Weights) == 2 && F.Weights(2).Grams == 68.5, 'A changed weight is a weighing');
R.updateSubject(sw, struct('Notes', 'no weight'));
R.updateSubject(sw, struct('Weight', NaN));
assert(numel(F.Weights) == 2, 'No weight, or NaN, is not a weighing');
F.Throw = true;
R.updateSubject(sw, struct('Weight', 66));
assert(R.findSubject(sw).Weight == 66, 'A throwing registry must not cost the roster write');
F.Throw = false;
fprintf('PASS: weighings reach the registry, and a broken one is harmless\n');

% 6. SessionRecord and the session hooks -----------------------------------
dataFile = fullfile(root, 'G010', 'G010_260101T120000.mat');
mkdir(fileparts(dataFile));
Data = struct('TrialType', {0, 1, 0}, 'computerTimestamp', ...
    {datetime(2026,1,1,12,0,5), datetime(2026,1,1,12,0,9), datetime(2026,1,1,12,1,0)});
Info = struct('SessionUID', 'x');
save(dataFile, 'Data', 'Info');

RT = epsych.Runtime;
RT.ReviewMode = true;   % no dispatch on assigning TRIALS
RT.SessionUID = epsych.newUUID();
subj = epsych.DefaultSubject(struct('Name', 'G010', 'Sex', 'Male', 'Species', 'Gerbil'));
snap = struct('FormatVersion', 1, 'SessionUID', char(RT.SessionUID), ...
    'StartTime', datetime(2026,1,1,12,0,0), 'SelectorClass', 'epsych.DefaultTrialSelector', ...
    'EPsychMeta', struct('Version', '2.0', 'Checksum', 'abc123', 'StimgenChecksum', 'def456'), ...
    'Protocol', struct('protocolVersion', '7', 'Options', struct('trialFunc', 'cl_TrialFcn')));
RT.TRIALS = struct('Subject', subj, 'BoxID', 2, 'DataFilename', erase(dataFile, '.mat'), ...
    'DATA', Data, 'SessionInfo', snap);
CONFIG = struct('protocol_fn', fullfile(root, 'Detect_v2.eprot'), 'PROTOCOL', [], 'SUBJECT', subj, ...
    'ROSTER', epsych.ParameterDefaults.rosterLink(rosterFile, sw, p1));
FUNCS = struct('BehaviorGUI', 'cl_BehaviorGUI', 'SavingFcn', 'ep_SaveDataFcn');

rec = epsych.SessionRecord.fromRun(RT, CONFIG, 1, FUNCS = FUNCS);
assert(rec.SessionUID == RT.SessionUID(1), 'The record carries the SessionUID');
assert(rec.Subject == "G010" && rec.BoxID == 2 && rec.NumTrials == 3, 'Subject, box and trials');
assert(rec.DataFile == string(dataFile), 'The data file is found with its .mat extension');
assert(rec.RegistryID == "SUBJ-ID-10" && rec.SubjectID == string(sw), 'The roster link is read');
assert(rec.Project == "Detection" && rec.ProjectRegistryID == "proj-uuid-2", 'The project is read');
assert(rec.ProtocolName == "Detect_v2" && rec.ProtocolVersion == "7" && rec.Paradigm == "cl_TrialFcn", 'Protocol');
assert(rec.EndTime == datetime(2026,1,1,12,1,0, 'TimeZone', 'local') && ~isempty(rec.StartTime.TimeZone), ...
    'Times are zoned, the end from the last trial');
assert(rec.BehaviorGUI == "cl_BehaviorGUI" && rec.EPsychChecksum == "abc123", 'Session functions and provenance');
assert(isempty(rec.Problems), 'A complete session has no problems: %s', strjoin(rec.Problems, '; '));

epsych.SubjectRegistry.notifySessionSaved(RT, CONFIG, FUNCS);
assert(numel(F.Sessions) == 1 && F.Sessions{1}(1).SessionUID == RT.SessionUID(1), ...
    'notifySessionSaved hands the registry one record per subject');
RT.isTest = true;
epsych.SubjectRegistry.notifySessionSaved(RT, CONFIG, FUNCS);
assert(numel(F.Sessions) == 1, 'A Preview is never recorded');
RT.isTest = false;
F.Throw = true;
epsych.SubjectRegistry.notifySessionSaved(RT, CONFIG, FUNCS);
epsych.SubjectRegistry.notifySessionRunning(true);
F.Throw = false;
epsych.SubjectRegistry.notifySessionRunning(true);
epsych.SubjectRegistry.notifySessionRunning(false);
assert(isequal(F.Running, [true false]), 'sessionRunning is passed through');

recMissing = epsych.SessionRecord.fromRun(RT, struct('protocol_fn', '', 'ROSTER', []), 1);
assert(recMissing.SessionUID == RT.SessionUID(1), 'A record without CONFIG still names its session');
delete(dataFile);
recGone = epsych.SessionRecord.fromRun(RT, CONFIG, 1);
assert(recGone.DataFile == "" && any(contains(recGone.Problems, 'not found')), 'A missing file is a problem, not an error');
fprintf('PASS: SessionRecord describes a run; the hooks reach the registry and survive a broken one\n');

% 7. Session warnings come from the cache only -----------------------------
F.Status = epsych.SubjectRegistry.emptyStatus(["SUBJ-ID-10" "SUBJ-ID-5"]);
F.Status.Known(:) = true;
F.Status.Endpointed(1) = true;
F.Status.EndpointAt(1) = datetime(2026,10,3, 'TimeZone', 'local');
F.Status.WeightG(2) = 50;
F.Status.BaselineG(2) = 80;
F.Status.AsOf(:) = datetime('now', 'TimeZone', 'local');
subs = [R.findSubject(sw), R.findByRegistryID('SUBJ-ID-5'), R.findSubject('G001')];
W = F.sessionWarnings(subs);
assert(numel(W) == 2 && W(1).Kind == "endpoint" && W(2).Kind == "low_weight", 'Endpoint and low-weight warnings');
assert(contains(W(1).Message, '2026-10-03') && contains(W(2).Message, '62%'), 'Warnings say when and how much');
fprintf('PASS: sessionWarnings flags endpoints and low weight\n');

clear cleanupDir cleanupReg cleanupPrefs
fprintf('ALL SUBJECT REGISTRY SMOKE TESTS PASSED\n');
end

% -----------------------------------------------------------------------
function localExpectError(fcn, id)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, id), 'Expected %s, got %s: %s', id, ME.identifier, ME.message);
    return
end
error('smoke:noError', 'Expected error %s was not thrown', id);
end

function localRestoreAll(savedSubjectPrefs, savedEPsychPrefs)
localRestorePrefs('ep_RunExpt_Subjects', savedSubjectPrefs);
localRestorePrefs('EPsych', savedEPsychPrefs);
end

function saved = localSavePrefs(group)
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

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

function localRemoveDir(root)
if isfolder(root)
    try
        rmdir(root, 's');
    catch ME
        vprintf(2, ME);
    end
end
end
