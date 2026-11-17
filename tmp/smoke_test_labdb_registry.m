function smoke_test_labdb_registry(carasRoot)
% smoke_test_labdb_registry()
% smoke_test_labdb_registry(carasRoot)
% labdb.Registry end to end over labclient.FakeBackend: no server, no
% Database Toolbox, a temporary client folder, preference store and vault, so
% nothing of the user's is read or written. A session saved in EPsych becomes
% one behavior event (its id the SessionUID) with the data file as its output;
% sending twice writes once; a session saved again replaces its record while
% it waits and registers the new bytes as replacing the old file once sent; an
% unreachable server leaves the record waiting and costs a bounded wait;
% sending stands down while a session runs; an animal the database does not
% have holds the record until it is assigned; a weighing is a husbandry event
% and a same-day correction replaces it; the subject cache answers offline and
% drives sessionWarnings.
%
% Needs the CarasLabDB checkout (its @CarasLabDB class and +labclient package):
% on the path already, or CARASLABDB, or CARASLABDB_ROOT, or a sibling of the
% EPsych checkout. Without it the test says SKIPPED and passes.
%
%   matlab -batch "cd('tmp'); smoke_test_labdb_registry"
%
% See also: labdb.Registry, labdb.SessionBundle, smoke_test_subject_registry

epsych_startup
if nargin < 1, carasRoot = ""; end
if ~localFindCaras(string(carasRoot))
    fprintf('SKIPPED: the CarasLabDB checkout (with +labclient) is not on the path.\n');
    return
end
[ok, why] = labdb.Registry.isAvailable();
assert(ok, 'labdb.Registry should be available once CarasLabDB is on the path: %s', why);

% --- an isolated client: prefs file, client folder, vault, backend, no timer
savedEPsych = localSavePrefs('EPsych');
savedSubj   = localSavePrefs('ep_RunExpt_Subjects');
cleanupPrefs = onCleanup(@() localRestore(savedEPsych, savedSubj));
cleanupReg = onCleanup(@() epsych.SubjectRegistry.current(Reset=true));
restorePrefs   = labclient.Prefs.useTemporary();
restoreFolder  = labclient.DB.useTemporary();
restoreSecrets = labclient.Secrets.useFake();
fake = labclient.FakeBackend();
restoreBackend = labclient.DB.useBackend(@() fake);
manual = labclient.Sync.useManual();

root = fullfile(tempdir, 'epsych_labdb_smoke');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));

s = labclient.Settings.defaults();
s.Enabled = true;
s.Server = "fake-server";
s.Username = fake.Login;
s.PersonId = fake.PersonId;
s.ConnectTimeout = 2;
s.Roots = struct('Name', "rig-d", 'Path', string(root));
labclient.Settings.save(s);
labclient.Secrets.setFake(s, fake.Password);

fake.Roots = table(1, "rig-d", "", 'VariableNames', {'root_id', 'name', 'description'});
fake.Projects = table("proj-1", "Detection", 'VariableNames', {'project_id', 'name'});
fake.Subjects = table(["SUBJ-ID-10"; "SUBJ-ID-11"], ["proj-1"; "proj-1"], ...
    ["meriones_unguiculatus"; "meriones_unguiculatus"], ["M"; "F"], ...
    'VariableNames', {'subject_id', 'project_id', 'species_code', 'sex'});

R = labdb.Registry();
epsych.SubjectRegistry.current(Use = R);
assert(R.isEnabled() && R.label() == "Lab DB", 'The adapter is enabled');

% 1. A session becomes one behavior event -------------------------------
[RT, CONFIG, dataFile] = localRun(root, 'SUBJ-ID-10');
epsych.SubjectRegistry.notifySessionSaved(RT, CONFIG, struct('BehaviorGUI', 'cl_GUI', 'SavingFcn', 'ep_SaveDataFcn'));
uid = RT.SessionUID(1);
[b, st] = labclient.Outbox.read(uid);
assert(st == "pending" && b.record.event.event_type == "behavior", 'The session waits in the outbox as a behavior event');
assert(numel(b.record.outputs) == 1 && labclient.Bundles.isSealed(b), 'Its data file is its output, hashed');
res = labclient.Sync.flush(Budget = 20);
[~, st] = labclient.Outbox.read(uid);
assert(st == "done", 'The session is sent (%s)', localText(res));
E = localEvents(fake, uid);
assert(numel(E) == 1 && string(E.subject_id) == "SUBJ-ID-10", 'The event is the session, for its subject');
assert(E.detail.trials_completed == 3 && string(E.detail.paradigm) == "cl_TrialFcn", 'Its detail is the session''s');
A = localFiles(fake, uid);
assert(height(A) == 1 && endsWith(A.relative_path(1), "G_SUBJ-ID-10.mat"), 'The data file is registered under the rig root');
fprintf('PASS: a saved session is one behavior event with its data file\n');

% 2. Sending twice writes once; saving again replaces the file ------------
epsych.SubjectRegistry.notifySessionSaved(RT, CONFIG);   % same bytes, already sent
labclient.Sync.flush(Budget = 10);
assert(numel(localEvents(fake, uid)) == 1, 'A resend writes nothing new');
localResave(dataFile);
epsych.SubjectRegistry.notifySessionSaved(RT, CONFIG);
labclient.Sync.flush(Budget = 20);
A = localFiles(fake, uid);
assert(height(A) == 2, 'A session saved again after sending registers the new file (%d)', height(A));
assert(any(fake.Dispositions.disposition == "replaced"), 'The earlier file is recorded as replaced');
fprintf('PASS: a resend writes once; a later save replaces the file\n');

% 3. Saving again before sending replaces the record ----------------------
[RT2, C2, f2] = localRun(root, 'SUBJ-ID-11');
epsych.SubjectRegistry.notifySessionSaved(RT2, C2);
localResave(f2);
epsych.SubjectRegistry.notifySessionSaved(RT2, C2);
T = labclient.Outbox.list();
assert(nnz(T.id == RT2.SessionUID(1)) == 1, 'One record per session, however often it is saved');
labclient.Sync.flush(Budget = 20);
assert(height(localFiles(fake, RT2.SessionUID(1))) == 1, ...
    'Only the last save is registered');
fprintf('PASS: saving again before sending replaces the waiting record\n');

% 4. An unreachable server costs a bounded wait, and the record waits -----
fake.Reachable = false;
labclient.DB.disconnect();
[RT3, C3] = localRun(root, 'SUBJ-ID-10');
epsych.SubjectRegistry.notifySessionSaved(RT3, C3);
t0 = tic;
labclient.Sync.flush(Budget = 3);
waited = toc(t0);
[~, st] = labclient.Outbox.read(RT3.SessionUID(1));
assert(st == "pending", 'With the server away the record waits (%s)', st);
assert(waited < s.ConnectTimeout + 5, 'An unreachable server costs a bounded wait (%.1f s)', waited);
stR = R.status();
assert(stR.Pending >= 1, 'The lamp counts what waits');
assert(stR.State == "offline", 'The lamp reads offline (%s)', stR.State);
fake.Reachable = true;
% The client waits out its backoff before trying again; a person's Send now
% (or this) tries at once.
labclient.DB.connect(Force = true);
fprintf('PASS: offline, the record waits and nothing hangs (%.1f s)\n', waited);

% 5. Sending stands down while a session runs ----------------------------
epsych.SubjectRegistry.notifySessionRunning(true);
assert(labclient.Sync.suspended(), 'A run suspends the sender');
epsych.SubjectRegistry.notifySessionRunning(false);
assert(~labclient.Sync.suspended(), 'The end of the save resumes it');
labclient.Sync.flush(Budget = 20);
[~, st] = labclient.Outbox.read(RT3.SessionUID(1));
assert(st == "done", 'The waiting record goes once the server is back');
fprintf('PASS: the sender stands down for a run and resumes after\n');

% 6. An animal the database does not have holds the record ----------------
[RT4, C4] = localRun(root, 'G999');
epsych.SubjectRegistry.notifySessionSaved(RT4, C4);
labclient.Sync.flush(Budget = 20);
[~, st] = labclient.Outbox.read(RT4.SessionUID(1));
assert(st == "held", 'A session of an unknown animal is held (%s)', st);
H = labclient.Sync.subjectHolds();
assert(height(H) >= 1, 'It is listed for a person to assign');
fprintf('PASS: an animal the database does not have holds its record\n');

% 7. Weighings ------------------------------------------------------------
subj = struct('Name', 'G010', 'RegistryID', 'SUBJ-ID-10', 'SubjectID', 'S_1');
R.weightMeasured(subj, 71, datetime('now'));
R.weightMeasured(subj, 70.5, datetime('now'));   % a same-day correction
T = labclient.Outbox.list();
hus = 0;
for k = 1:height(T)
    bb = labclient.Outbox.read(T.id(k));
    if bb.type == "event" && bb.record.event.event_type == "husbandry", hus = hus + 1; end
end
assert(hus == 1, 'A same-day correction replaces the waiting weighing (%d)', hus);
labclient.Sync.flush(Budget = 20);
C = fake.subjectCurrent("SUBJ-ID-10");
assert(C.latest_weight_g(1) == 70.5, 'The corrected weight reaches the database');
s.Enabled = false;
labclient.Settings.save(s);
before = height(labclient.Outbox.list());
R.weightMeasured(subj, 69, datetime('now'));
assert(height(labclient.Outbox.list()) == before, 'Nothing is recorded with the lab database turned off');
s.Enabled = true;
labclient.Settings.save(s);
fprintf('PASS: a weighing is a husbandry event, and a same-day fix replaces it\n');

% 8. The subject cache answers offline and drives the warnings -------------
fake.SubjectInfo = table("SUBJ-ID-11", NaT, datetime(2026,10,3, 'TimeZone', 'UTC'), ...
    'VariableNames', {'subject_id', 'date_of_birth', 'endpoint_at'});
rep = R.refreshStatus(["SUBJ-ID-10" "SUBJ-ID-11"]);
assert(rep.OK, 'Refresh reads the database: %s', rep.Message);
fake.Reachable = false;
labclient.DB.disconnect();
Tst = R.subjectStatus(["SUBJ-ID-10" "SUBJ-ID-11"]);
assert(all(Tst.Known) && ~Tst.Endpointed(1) && Tst.Endpointed(2), 'The cache answers offline');
assert(Tst.WeightG(1) == 70.5 && ~isnat(Tst.AsOf(1)), 'It carries the latest weight and its age');
W = R.sessionWarnings(struct('Name', {'G010', 'G011'}, 'RegistryID', {'SUBJ-ID-10', 'SUBJ-ID-11'}));
assert(numel(W) == 1 && W(1).Kind == "endpoint", 'sessionWarnings flags the endpointed animal');
Tf = R.findSubjects(struct('CacheOnly', true));
assert(height(Tf) == 0, 'CacheOnly never asks the server');
fake.Reachable = true;
Tf = R.findSubjects(struct('Project', "proj-1"));
assert(height(Tf) == 2 && all(Tf.Project == "Detection") && any(Tf.Sex == "Male"), ...
    'findSubjects lists a project''s animals in the roster''s words');
P = R.projects();
assert(height(P) == 1 && P.Name == "Detection", 'projects lists the database''s projects');
fprintf('PASS: the cache answers offline and drives the warnings\n');

% 9. A real unreachable server: the real backend's TCP probe, bounded -------
% A non-routable address never answers, so this is the wait a rig pays when
% the server is down -- through labclient.CarasBackend, not the fake.
clear restoreBackend
labclient.DB.disconnect();
s.Server = "10.255.255.1";
s.ConnectTimeout = 2;
labclient.Settings.save(s);
labclient.Secrets.setFake(s, "pw");
[RT5, C5] = localRun(root, 'SUBJ-ID-10');
epsych.SubjectRegistry.notifySessionSaved(RT5, C5);
t0 = tic;
labclient.Sync.flush(Budget = 5);
waited = toc(t0);
[~, st] = labclient.Outbox.read(RT5.SessionUID(1));
assert(st == "pending", 'Against an unreachable server the record waits (%s)', st);
assert(waited < 8, 'An unreachable server costs at most about ConnectTimeout (%.1f s)', waited);
assert(R.status().State == "offline", 'The lamp reads offline');
t0 = tic;
labclient.Sync.flush(Budget = 5);
again = toc(t0);
assert(again < 1, 'While backing off, a second try does not wait again (%.1f s)', again);
fprintf('PASS: a real unreachable server costs %.1f s once, then nothing while backing off\n', waited);

clear manual restoreBackend restoreSecrets restoreFolder restorePrefs cleanupDir cleanupReg cleanupPrefs
fprintf('ALL LABDB REGISTRY SMOKE TESTS PASSED\n');
end

% -----------------------------------------------------------------------
function [RT, CONFIG, dataFile] = localRun(root, name)
% A finished one-subject run whose data file is under the rig root.
folder = fullfile(root, name);
if ~isfolder(folder), mkdir(folder); end
dataFile = fullfile(folder, ['G_' name '.mat']);
Data = struct('TrialType', {0, 1, 0}, 'computerTimestamp', ...
    {datetime(2026,1,1,12,0,5), datetime(2026,1,1,12,0,9), datetime(2026,1,1,12,1,0)});
RT = epsych.Runtime;
RT.ReviewMode = true;
RT.SessionUID = epsych.newUUID();
Info = struct('SessionUID', char(RT.SessionUID));
save(dataFile, 'Data', 'Info');
subj = epsych.DefaultSubject(struct('Name', name, 'Sex', 'Male', 'Species', 'Gerbil'));
snap = struct('FormatVersion', 1, 'SessionUID', char(RT.SessionUID), ...
    'StartTime', datetime(2026,1,1,12,0,0), 'Protocol', struct('protocolVersion', '3', ...
    'Options', struct('trialFunc', 'cl_TrialFcn')));
RT.TRIALS = struct('Subject', subj, 'BoxID', 1, 'DataFilename', dataFile, 'DATA', Data, 'SessionInfo', snap);
CONFIG = struct('protocol_fn', fullfile(root, 'Detect.eprot'), 'PROTOCOL', [], 'SUBJECT', subj, 'ROSTER', []);
end

function localResave(f)
% New bytes at the same path, as RunExpt's Save Data would write.
S = load(f);
S.Resaved = datetime('now');
save(f, '-struct', 'S');
end

function E = localEvents(fake, id)
E = fake.Events(string({fake.Events.event_id}) == string(id));
end

function A = localFiles(fake, id)
A = fake.Artifacts(fake.Artifacts.produced_by_event_id == string(id), :);
end

function t = localText(res)
t = '';
try t = char(string(res.message)); catch, end
end

function found = localFindCaras(root)
found = exist('labclient.Settings', 'class') == 8 && exist('CarasLabDB', 'class') == 8;
if found, return, end
cands = root;
cands(end+1) = string(getenv('CARASLABDB'));
cands(end+1) = string(getenv('CARASLABDB_ROOT'));
cands(end+1) = string(fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'CarasLabDB'));
for c = cands
    if c ~= "" && isfolder(fullfile(c, '+labclient'))
        addpath(c);
        found = exist('labclient.Settings', 'class') == 8;
        if found, return, end
    end
end
end

function saved = localSavePrefs(group)
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

function localRestore(a, b)
localRestorePrefs('EPsych', a);
localRestorePrefs('ep_RunExpt_Subjects', b);
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
