function smoke_test_session_record_settings
% smoke_test_session_record_settings
% What a trial record holds of buffers and of stimuli is the STUDY's choice:
% two yes/no session settings on each roster membership (RecordBuffers,
% RecordStimulusSettings), stamped from the project's Session Defaults,
% agreed across a batch, put on the session at commit, handed to the runtime
% at Run, and saved with the session.
%
% Verifies:
%   1) the three places that state the built-in defaults agree: the roster's
%      SESSION_FLAG_DEFAULTS, epsych.Runtime, and a fresh RunExpt session
%   2) sessionFlag / sessionFlagValue: the forms accepted, and that "not
%      stated" IS the built-in default
%   3) a project stores them, a reload keeps them, a bad value is refused and
%      nothing is created
%   4) assign stamps them; updateMembership diverges one subject;
%      reapplyTemplate brings it back; updateProject does not reach members;
%      copyProject carries them, and an override wins
%   5) a roster written before the fields existed opens as "not stated",
%      which means what every session recorded then
%   6) commit: the agreed values land on the session; a batch that states
%      nothing puts the built-in defaults BACK rather than inheriting the
%      last batch's; so does a batch with no project
%   7) commit: stating the default and stating nothing agree; a real
%      disagreement refuses the batch, names the field, and changes nothing
%   8) a real Run: the runtime gets the study's values, and the session's
%      Info records them
%   9) an Info from before the fields existed reads as buffers recorded,
%      stimuli as objects
%
% Opens RunExpt windows. Run headless:
%   matlab -batch "run('tmp/smoke_test_session_record_settings.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'detection_task'));

fprintf('\n=== smoke_test_session_record_settings ===\n');

% --- pref hygiene: the roster path is a machine preference ------------------
groups = {'ep_RunExpt_FUNCS','ep_RunExpt_TIMER','ep_RunExpt_Subjects','ep_RunExpt_Setup','RunExpt'};
saved = cellfun(@(g) localSavePrefs(g), groups, 'uni', 0);
cleanupPrefs = onCleanup(@() localRestoreAll(groups, saved));

root = fullfile(tempdir, 'epsych_session_record_settings');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));
cleanupFigs = onCleanup(@() delete(findall(groot,'Type','figure','Tag','RunExpt')));

dataRoot = fullfile(root, 'data');
mkdir(dataRoot);
protoFile = fullfile(root, 'DetectionExample.eprot');
create_detection_protocol(protoFile);
assert(isfile(protoFile), 'the example protocol was not written');

FLAGS = epsych.SubjectRoster.SESSION_FLAG_FIELDS;
DFLT = epsych.SubjectRoster.SESSION_FLAG_DEFAULTS;

% --- 1. one set of built-in defaults ----------------------------------------
assert(all(ismember(FLAGS, epsych.SubjectRoster.SESSION_FIELDS)), ...
    'the yes/no settings must be session fields, so stamping and the commit check see them');
rt = epsych.Runtime;
assert(isequal(sort(FLAGS), sort(fieldnames(DFLT)')), ...
    'every yes/no setting needs a built-in default, and only those');
for f = FLAGS
    assert(isequal(rt.(f{1}), DFLT.(f{1})), ...
        'SESSION_FLAG_DEFAULTS.%s and epsych.Runtime''s default disagree', f{1});
    % sessionFlagValue names the fields as literals in its arguments block.
    assert(islogical(epsych.SubjectRoster.sessionFlagValue(f{1}, NaN)), ...
        'sessionFlagValue does not accept %s', f{1});
end
delete(rt);
assert(DFLT.RecordBuffers == true && DFLT.RecordStimulusSettings == false, ...
    'the built-in defaults must stay what every session recorded before the settings existed');

delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx = epsych.RunExpt(ReuseExisting = false);
assert(rx.FUNCS.RecordBuffers == true && rx.FUNCS.RecordStimulusSettings == false, ...
    'a fresh session starts on the built-in defaults');
fprintf('PASS: 1 the roster, the runtime and a fresh session state the same defaults\n');

% --- 2. the canonical forms --------------------------------------------------
yes = {true, 1, 'on', "yes", 'TRUE', '1'};
no = {false, 0, 'off', "no", 'False', '0'};
unstated = {NaN, [], '', "", 'inherit', 'default'};
for k = 1:numel(yes)
    [v, ok] = epsych.SubjectRoster.sessionFlag(yes{k});
    assert(ok && v == 1, 'form %d of yes was not read as 1', k);
end
for k = 1:numel(no)
    [v, ok] = epsych.SubjectRoster.sessionFlag(no{k});
    assert(ok && v == 0, 'form %d of no was not read as 0', k);
end
for k = 1:numel(unstated)
    [v, ok] = epsych.SubjectRoster.sessionFlag(unstated{k});
    assert(ok && isnan(v), 'form %d of not-stated was not read as NaN', k);
end
for bad = {2, 'maybe', [1 0], struct()}
    [v, ok] = epsych.SubjectRoster.sessionFlag(bad{1});
    assert(~ok && isnan(v), 'an unrecognized value must come back NaN and not ok');
end
assert(epsych.SubjectRoster.sessionFlagValue('RecordBuffers', NaN) == true ...
    && epsych.SubjectRoster.sessionFlagValue('RecordBuffers', 0) == false ...
    && epsych.SubjectRoster.sessionFlagValue('RecordStimulusSettings', NaN) == false ...
    && epsych.SubjectRoster.sessionFlagValue('RecordStimulusSettings', 1) == true, ...
    'not stated must mean the built-in default, a stated value itself');
fprintf('PASS: 2 the accepted forms, and not-stated is the built-in default\n');

% --- 3. a project stores them ------------------------------------------------
rosterFile = fullfile(root, 'lab.esub');
epsych.SubjectRoster.setConfiguredFile(rosterFile);
R = epsych.SubjectRoster(rosterFile);

plain = R.addProject('Plain Study', DefaultProtocol = protoFile, DefaultDataPath = dataRoot, ...
    BehaviorGUI = epsych.SubjectRoster.BEHAVIORGUI_NONE);
p = R.findProject(plain);
assert(isnan(p.RecordBuffers) && isnan(p.RecordStimulusSettings), ...
    'a project that states neither stores "not stated"');

lean = R.addProject('Lean Study', DefaultProtocol = protoFile, DefaultDataPath = dataRoot, ...
    BehaviorGUI = epsych.SubjectRoster.BEHAVIORGUI_NONE, ...
    RecordBuffers = false, RecordStimulusSettings = true);
p = epsych.SubjectRoster(rosterFile).findProject(lean);
assert(isa(p.RecordBuffers, 'double') && p.RecordBuffers == 0 && p.RecordStimulusSettings == 1, ...
    'the stated settings did not survive a reload as 0 and 1');

nBefore = numel(R.Projects);
threw = '';
try
    R.addProject('Bad Study', RecordBuffers = 'sometimes');
catch ME
    threw = ME.identifier;
end
assert(strcmp(threw, 'epsych:SubjectRoster:InvalidSessionFlag') && numel(R.Projects) == nBefore, ...
    'a bad value must be refused and create nothing (got "%s")', threw);
fprintf('PASS: 3 a project stores them, a reload keeps them, a bad value is refused\n');

% --- 4. template, membership, copy ------------------------------------------
s1 = R.addSubject(struct('Name','RS1','Sex','Male','Species','Mouse'));
s2 = R.addSubject(struct('Name','RS2','Sex','Male','Species','Mouse'));
for s = {s1, s2}
    R.assign(s{1}, lean);
    R.rememberProtocol(s{1}, lean, protoFile);
end
m = R.findMembership(s1, lean);
assert(m.RecordBuffers == 0 && m.RecordStimulusSettings == 1, 'assign did not stamp the template');

R.updateMembership(s2, lean, struct('RecordBuffers', true, 'SavingFcn', 'ep_SaveDataFcn'));
m2 = R.findMembership(s2, lean);
assert(isa(m2.RecordBuffers, 'double') && m2.RecordBuffers == 1 && m2.RecordStimulusSettings == 1, ...
    'updateMembership should change the one setting named, as a number');
assert(ischar(m2.SavingFcn) && strcmp(m2.SavingFcn, 'ep_SaveDataFcn'), ...
    'a text setting written alongside must stay text');

threw = '';
try
    R.updateMembership(s2, lean, struct('RecordStimulusSettings', 7));
catch ME
    threw = ME.identifier;
end
assert(strcmp(threw, 'epsych:SubjectRoster:InvalidSessionFlag') ...
    && R.findMembership(s2, lean).RecordStimulusSettings == 1, ...
    'a refused membership value must leave the record alone');

R.updateProject(lean, struct('RecordStimulusSettings', false));
assert(R.findProject(lean).RecordStimulusSettings == 0, 'updateProject should store the new template value');
assert(R.findMembership(s1, lean).RecordStimulusSettings == 1, ...
    'a template edit must not reach an existing member');
R.updateProject(lean, struct('RecordStimulusSettings', true));

rep = R.reapplyTemplate({s2}, lean);
assert(isscalar(rep.updated) && R.findMembership(s2, lean).RecordBuffers == 0, ...
    'reapplyTemplate should put the member back on the template');

copyId = R.copyProject(lean, 'Lean Study Phase 2', IncludeSubjects = true);
pc = R.findProject(copyId);
assert(pc.RecordBuffers == 0 && pc.RecordStimulusSettings == 1, 'copyProject should carry both settings');
assert(R.findMembership(s1, copyId).RecordBuffers == 0, 'and stamp them on the copied members');
overId = R.copyProject(lean, 'Lean Study Phase 3', RecordBuffers = true);
assert(R.findProject(overId).RecordBuffers == 1 && R.findProject(overId).RecordStimulusSettings == 1, ...
    'a stated override wins and the rest follows the source');
fprintf('PASS: 4 stamped at assign, diverged, re-applied, and carried by a copy\n');

% --- 5. a roster written before the fields existed ---------------------------
legacyFile = fullfile(root, 'legacy.esub');
S = load(rosterFile, '-mat');
formatVersion = S.formatVersion;
subjects      = S.subjects;
meta          = S.meta;
projects      = rmfield(S.projects, FLAGS);
memberships   = rmfield(S.memberships, FLAGS);
save(legacyFile, 'formatVersion', 'subjects', 'projects', 'memberships', 'meta', '-mat');

Rold = epsych.SubjectRoster(legacyFile);
assert(isempty(Rold.LoadError) && Rold.IsWritable, 'an older roster must open normally: %s', Rold.LoadError);
assert(all(isnan([Rold.Projects.RecordBuffers])) && all(isnan([Rold.Projects.RecordStimulusSettings])) ...
    && all(isnan([Rold.Memberships.RecordBuffers])) && all(isnan([Rold.Memberships.RecordStimulusSettings])), ...
    'an older roster should read as "not stated" throughout');
mo = Rold.Memberships(1);
assert(epsych.SubjectRoster.sessionFlagValue('RecordBuffers', mo.RecordBuffers) == true ...
    && epsych.SubjectRoster.sessionFlagValue('RecordStimulusSettings', mo.RecordStimulusSettings) == false, ...
    'and that must mean what a session recorded before the settings existed');
fprintf('PASS: 5 an older roster opens as not stated, which means the old behaviour\n');

% --- 6. commit: landing, and no leftovers ------------------------------------
rep = R.assignToSession(rx, {s1}, ProjectID = lean, ReplaceExisting = true);
assert(rep.ok, 'the commit should have succeeded: %s', rep.message);
assert(rx.FUNCS.RecordBuffers == false && rx.FUNCS.RecordStimulusSettings == true, ...
    'the study''s settings should reach the session');
assert(contains(rep.message, 'buffers are left out') && contains(rep.message, 'recorded as their settings'), ...
    'the commit report should say what this session records: %s', rep.message);

s3 = R.addSubject(struct('Name','RS3','Sex','Male','Species','Mouse'));
R.assign(s3, plain);
R.rememberProtocol(s3, plain, protoFile);
rep = R.assignToSession(rx, {s3}, ProjectID = plain, ReplaceExisting = true);
assert(rep.ok, 'the second commit should have succeeded: %s', rep.message);
assert(rx.FUNCS.RecordBuffers == true && rx.FUNCS.RecordStimulusSettings == false, ...
    ['a study that states nothing must get the built-in defaults back, not the ' ...
     'last study''s choice of what a data file holds']);

rx.FUNCS.RecordBuffers = false;                    % as a previous batch left it
rx.FUNCS.RecordStimulusSettings = true;
rep = R.assignToSession(rx, {s3}, ReplaceExisting = true, ...
    Protocols = {protoFile});                       % no project context at all
assert(rep.ok, 'a commit with no project should succeed: %s', rep.message);
assert(rx.FUNCS.RecordBuffers == true && rx.FUNCS.RecordStimulusSettings == false, ...
    'a batch with no project gets the built-in defaults too');
fprintf('PASS: 6 the agreed values land on the session; nothing is inherited from the last batch\n');

% --- 7. commit: agreement is about what the setting means --------------------
mix = R.addProject('Mixed Study', DefaultProtocol = protoFile, DefaultDataPath = dataRoot, ...
    BehaviorGUI = epsych.SubjectRoster.BEHAVIORGUI_NONE);
sa = R.addSubject(struct('Name','MX1','Sex','Male','Species','Mouse'));
sb = R.addSubject(struct('Name','MX2','Sex','Male','Species','Mouse'));
for s = {sa, sb}
    R.assign(s{1}, mix);
    R.rememberProtocol(s{1}, mix, protoFile);
end
R.updateMembership(sb, mix, struct('RecordBuffers', true, 'RecordStimulusSettings', false));
rep = R.assignToSession(rx, {sa, sb}, ProjectID = mix, ReplaceExisting = true);
assert(rep.ok && isempty(rep.mismatch), ...
    'stating the built-in default and stating nothing are one setting: %s', rep.message);

R.updateMembership(sb, mix, struct('RecordBuffers', false));
before = {rx.FUNCS.RecordBuffers, rx.FUNCS.RecordStimulusSettings, numel(rx.CONFIG)};
rep = R.assignToSession(rx, {sa, sb}, ProjectID = mix, ReplaceExisting = true);
assert(rep.aborted && ~rep.ok, 'a real disagreement must refuse the batch');
assert(isscalar(rep.mismatch) && strcmp(rep.mismatch.Field, 'RecordBuffers'), ...
    'report.mismatch should name RecordBuffers and nothing else');
assert(contains(rep.message, 'RecordBuffers') && contains(rep.message, 'yes') && contains(rep.message, 'no'), ...
    'the refusal should read as yes vs no: %s', rep.message);
assert(isequal(before, {rx.FUNCS.RecordBuffers, rx.FUNCS.RecordStimulusSettings, numel(rx.CONFIG)}), ...
    'a refused batch must leave the session as it was');
delete(rx);
fprintf('PASS: 7 the default and not-stated agree; a real disagreement refuses the batch\n');

% --- 8. a real Run -----------------------------------------------------------
rx = epsych.RunExpt("Lean Study", Subjects = "RS1", Run = true, ReuseExisting = false);
assert(localWaitFor(@() rx.STATE == PRGMSTATE.RUNNING, 30), ...
    'the session never reached RUNNING (got %s)', char(string(rx.STATE)));
assert(rx.RUNTIME.RecordBuffers == false && rx.RUNTIME.RecordStimulusSettings == true, ...
    'the runtime should run on the study''s settings');
info = epsych.SessionSnapshot.forSubject(rx.RUNTIME, 1);
assert(islogical(info.RecordBuffers) && info.RecordBuffers == false ...
    && info.RecordStimulusSettings == true, ...
    'the session''s Info should record what its trial records hold');
rx.halt;
assert(localWaitFor(@() rx.STATE == PRGMSTATE.STOP, 30), ...
    'halt never reached STOP (got %s)', char(string(rx.STATE)));
delete(rx);

rx = epsych.RunExpt("Plain Study", Subjects = "RS3", Run = true, ReuseExisting = false);
assert(localWaitFor(@() rx.STATE == PRGMSTATE.RUNNING, 30), ...
    'the second session never reached RUNNING (got %s)', char(string(rx.STATE)));
assert(rx.RUNTIME.RecordBuffers == true && rx.RUNTIME.RecordStimulusSettings == false, ...
    'a study that states nothing runs on the built-in defaults');
info = epsych.SessionSnapshot.forSubject(rx.RUNTIME, 1);
assert(info.RecordBuffers == true && info.RecordStimulusSettings == false, 'and its Info says so');
rx.halt;
assert(localWaitFor(@() rx.STATE == PRGMSTATE.STOP, 30), 'halt never reached STOP');
delete(rx);
fprintf('PASS: 8 a real Run gets the study''s settings, and Info records them\n');

% --- 9. an Info from before the fields ---------------------------------------
old = rmfield(info, FLAGS);
back = epsych.SessionSnapshot.fromInfo(old);
assert(back.RecordBuffers == true && back.RecordStimulusSettings == false, ...
    'a snapshot written before the fields existed recorded buffers, and stimuli as objects');
legacy = epsych.SessionSnapshot.fromInfo(struct('Subject', struct('Name','X'), 'isTest', false), Quiet = true);
assert(legacy.RecordBuffers == true && legacy.RecordStimulusSettings == false, ...
    'so did a file from before the snapshot existed');
fprintf('PASS: 9 an older Info reads as buffers recorded, stimuli as objects\n');

epsych.SubjectRoster.setConfiguredFile('');
fprintf('smoke_test_session_record_settings: ALL PASS\n');
end


% -----------------------------------------------------------------------
function tf = localWaitFor(cond, timeoutSec)
% Poll a condition during pause() -- timers fire while paused.
t0 = tic;
tf = false;
while toc(t0) < timeoutSec
    if cond(), tf = true; return, end
    pause(0.2);
end
end

% -----------------------------------------------------------------------
function saved = localSavePrefs(group)
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

% -----------------------------------------------------------------------
function localRestoreAll(groups, saved)
for i = 1:numel(groups)
    if ispref(groups{i}), rmpref(groups{i}); end
    if saved{i}.existed
        fn = fieldnames(saved{i}.values);
        for k = 1:numel(fn)
            setpref(groups{i}, fn{k}, saved{i}.values.(fn{k}));
        end
    end
end
end

% -----------------------------------------------------------------------
function localRemoveDir(root)
try
    if isfolder(root), rmdir(root, 's'); end
catch
    % A file handle the OS has not released yet; the temp folder is fine.
end
end
