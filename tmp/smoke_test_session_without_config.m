function smoke_test_session_without_config
% smoke_test_session_without_config
% The proof that the .ecfg Config subsystem is gone and the subject's roster
% membership carries the session configuration instead.
%
% Verifies:
%   1) the retired pref floor is GONE: poisoned ep_RunExpt_FUNCS /
%      ep_RunExpt_TIMER values are never read
%   2) a project template is stamped onto memberships at assign, template
%      edits do not propagate, and copyProject stamps from the NEW template
%   3) diverged memberships refuse the batch commit machine-readably, with
%      nothing half-committed
%   4) after reapplyTemplate the commit succeeds, the Config subsystem is
%      absent from the session window, and every FUNCS field -- the four
%      TIMERfcn callbacks included -- equals the membership values
%   5) a single-subject commit configures the whole session (the headline:
%      selecting a subject selects all config required to run it)
%   6) closing the session writes nothing back to the machine preferences
%   7) epsych.RunExpt("<project>") assembles the session from the roster, and
%      Run=true reaches RUNNING and halts to STOP
%   8) membership session fields survive a roster round trip, and an
%      old-shape roster reads back as all-inherit
%   9) the deleted shims stay deleted
%
% Run headless: matlab -batch "run('tmp/smoke_test_session_without_config.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'detection_task'));

% --- pref hygiene ---------------------------------------------------------
groups = {'ep_RunExpt_FUNCS','ep_RunExpt_TIMER','ep_RunExpt_Subjects','ep_RunExpt_Setup'};
saved = cellfun(@(g) localSavePrefs(g), groups, 'uni', 0);
cleanupPrefs = onCleanup(@() localRestoreAll(groups, saved));

root = fullfile(tempdir, 'epsych_session_without_config');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));
cleanupFigs = onCleanup(@() delete(findall(groot,'Type','figure','Tag','RunExpt')));

dataRoot = fullfile(root, 'data');
mkdir(dataRoot);

% A software-only protocol with a full run path.
protoFile = fullfile(root, 'DetectionExample.eprot');
create_detection_protocol(protoFile);
assert(isfile(protoFile), 'the example protocol was not written');

% 1. The pref floor is gone -------------------------------------------------
setpref('ep_RunExpt_TIMER','Start','poison_timer_start');
setpref('ep_RunExpt_TIMER','Period', 0.77);
setpref('ep_RunExpt_FUNCS','SavingFcn','poison_saving_fcn');
setpref('ep_RunExpt_FUNCS','BehaviorGUI','poison_gui');
setpref('ep_RunExpt_FUNCS','BoxFig','poison_boxfig');

delete(findall(groot,'Type','figure','Tag','RunExpt'));
rx = epsych.RunExpt(ReuseExisting=false);
assert(strcmp(rx.FUNCS.SavingFcn, 'ep_SaveDataFcn') ...
    && strcmp(rx.FUNCS.BehaviorGUI, 'ep_GenericGUI') ...
    && strcmp(rx.FUNCS.TIMERfcn.Start, 'ep_TimerFcn_Start') ...
    && rx.FUNCS.TimerPeriod == 0.01, ...
    'a poisoned preference was read: the pref floor is not gone');
fprintf('PASS: the retired preference floor is never read\n');

% 2. Template stamping, no propagation, copy stamping ------------------------
rosterFile = fullfile(root, 'lab.esub');
epsych.SubjectRoster.setConfiguredFile(rosterFile);
R = epsych.SubjectRoster(rosterFile);

pid = R.addProject('NoConfig Study', ...
    DefaultProtocol = protoFile, ...
    DefaultDataPath = dataRoot, ...
    SavingFcn = 'ep_SaveDataFcn', ...
    BehaviorGUI = epsych.SubjectRoster.BEHAVIORGUI_NONE, ...
    TimerPeriod = 0.02, ...
    TimerStartFcn = 'ep_TimerFcn_Start', ...
    TimerRunTimeFcn = 'ep_TimerFcn_RunTime', ...
    TimerStopFcn = 'ep_TimerFcn_Stop', ...
    TimerErrorFcn = 'ep_TimerFcn_Error', ...
    VideoRootDir = fullfile(dataRoot, 'video'), ...
    IntanRootDir = fullfile(dataRoot, 'intan'), ...
    IntanSettingsFile = fullfile(dataRoot, 'rhx.xml'));

s1 = R.addSubject(struct('Name','NC1','Sex','Male','Species','Mouse'));
s2 = R.addSubject(struct('Name','NC2','Sex','Male','Species','Mouse'));
R.assign(s1, pid);
R.assign(s2, pid);
R.rememberProtocol(s1, pid, protoFile);
R.rememberProtocol(s2, pid, protoFile);

p = R.findProject(pid);
for f = epsych.SubjectRoster.SESSION_FIELDS
    assert(isequaln(R.findMembership(s1, pid).(f{1}), p.(f{1})) ...
        && isequaln(R.findMembership(s2, pid).(f{1}), p.(f{1})), ...
        'assign did not stamp %s', f{1});
end

R.updateProject(pid, struct('SavingFcn','sentinel_fcn'));
assert(strcmp(R.findMembership(s1, pid).SavingFcn, 'ep_SaveDataFcn'), ...
    'a template edit propagated to an existing membership');
R.updateProject(pid, struct('SavingFcn','ep_SaveDataFcn'));

R.updateMembership(s1, pid, struct('TimerPeriod', 0.9));
cid = R.copyProject(pid, 'NoConfig Phase 2', IncludeSubjects = true, SavingFcn = 'phase2_save');
mc = R.findMembership(s1, cid);
assert(strcmp(mc.SavingFcn, 'phase2_save') && mc.TimerPeriod == 0.02, ...
    'copyProject must stamp from the NEW template, not carry per-subject divergence');
R.updateMembership(s1, pid, struct('TimerPeriod', 0.02));
fprintf('PASS: stamping, no-propagation, and copy stamping\n');

% 3. Mismatch refusal ---------------------------------------------------------
R.updateMembership(s2, pid, struct('TimerPeriod', 0.5));
nBefore = numel(rx.CONFIG);
rep = R.assignToSession(rx, {s1, s2}, ProjectID = pid);
assert(rep.aborted, 'diverged memberships must refuse the batch');
assert(~isempty(rep.mismatch) && any(strcmp({rep.mismatch.Field}, 'TimerPeriod')), ...
    'report.mismatch should name TimerPeriod');
assert(numel(rx.CONFIG) == nBefore && isempty(rx.CONFIG(1).SUBJECT), ...
    'a refused batch must leave CONFIG untouched');
fprintf('PASS: mismatch refusal, machine-readable, nothing half-committed\n');

% 4. Re-apply, commit, gap-closed assertions ---------------------------------
rep = R.reapplyTemplate({s1, s2}, pid);
assert(rep.ok && numel(rep.updated) == 2, 'reapplyTemplate should update both');
rep = R.assignToSession(rx, {s1, s2}, ProjectID = pid);
assert(rep.ok, 'the agreed commit should succeed: %s', rep.message);

assert(~ismethod(rx,'LoadConfig') && ~ismethod(rx,'SaveConfig'), 'a config method survived');
assert(~isprop(rx,'CurrentConfigFile'), 'CurrentConfigFile survived');
assert(~isfield(rx.H,'config_name'), 'the config label survived');
assert(isempty(findall(rx.H.figure1,'Type','uimenu','Label','Config')), ...
    'the Config menu survived');
assert(rx.STATE >= PRGMSTATE.READY, 'the session should be READY (got %s)', ...
    char(string(rx.STATE)));

m = R.findMembership(s1, pid);
assert(strcmp(rx.FUNCS.SavingFcn, m.SavingFcn) ...
    && strcmp(rx.FUNCS.TIMERfcn.Start,   m.TimerStartFcn) ...
    && strcmp(rx.FUNCS.TIMERfcn.RunTime, m.TimerRunTimeFcn) ...
    && strcmp(rx.FUNCS.TIMERfcn.Stop,    m.TimerStopFcn) ...
    && strcmp(rx.FUNCS.TIMERfcn.Error,   m.TimerErrorFcn) ...
    && rx.FUNCS.TimerPeriod == m.TimerPeriod ...
    && isempty(rx.FUNCS.BehaviorGUI), ...
    'the membership values did not all land on FUNCS');
fprintf('PASS: re-apply, commit, subsystem absent, FUNCS carries the membership\n');

% 5. Single-subject full-config commit (the headline) ------------------------
delete(rx);
rx = epsych.RunExpt(ReuseExisting=false);
rep = R.assignToSession(rx, {s1}, ProjectID = pid);
assert(rep.ok, 'single-subject commit failed: %s', rep.message);
assert(strcmp(char(rx.DefaultDataPath), dataRoot) ...
    && strcmp(rx.FUNCS.SavingFcn, 'ep_SaveDataFcn') ...
    && rx.FUNCS.TimerPeriod == 0.02 ...
    && strcmp(rx.PATHS.VideoRootDir, fullfile(dataRoot, 'video')) ...
    && strcmp(rx.PATHS.IntanRootDir, fullfile(dataRoot, 'intan')) ...
    && strcmp(rx.PATHS.IntanSettingsFile, fullfile(dataRoot, 'rhx.xml')), ...
    'one membership should configure the whole session');
fprintf('PASS: selecting one subject selects all config required to run it\n');

% 6. No pref write-back on close ---------------------------------------------
rx.FUNCS.SavingFcn = 'cl_SaveDataFcn';
rx.FUNCS.TIMERfcn.Start = 'some_custom_start';
before = cellfun(@(g) getpref(g), groups(1:2), 'uni', 0);
delete(rx);
after = cellfun(@(g) getpref(g), groups(1:2), 'uni', 0);
assert(isequaln(before, after), 'closing the session changed the machine preferences');
fprintf('PASS: closing the session persists nothing\n');

% 7. Scripted launch ----------------------------------------------------------
rx = epsych.RunExpt("NoConfig Study", ReuseExisting = false);
assert(numel(rx.CONFIG) == 2, 'the project launch should commit both members');
boxes = sort(arrayfun(@(c) c.SUBJECT.BoxID, rx.CONFIG));
assert(isequal(boxes, [1 2]), 'boxes should be 1-2 (got %s)', mat2str(boxes));
delete(rx);

% The Run leg stays single-subject: ExptDispatch takes hardware interfaces
% from CONFIG(1).PROTOCOL only.
rx = epsych.RunExpt("NoConfig Study", Subjects = "NC1", Run = true, ...
    ReuseExisting = false);
assert(localWaitFor(@() rx.STATE == PRGMSTATE.RUNNING, 30), ...
    'the session never reached RUNNING (got %s)', char(string(rx.STATE)));
pause(1);
rx.halt;
assert(localWaitFor(@() rx.STATE == PRGMSTATE.STOP, 30), ...
    'halt never reached STOP (got %s)', char(string(rx.STATE)));
delete(rx);
fprintf('PASS: epsych.RunExpt("<project>") assembles, runs, and halts\n');

% A stale .ecfg positional fails loudly with the migration message.
threw = '';
try
    epsych.RunExpt('yesterday.ecfg', ReuseExisting = false);
catch ME
    threw = ME.identifier;
end
assert(strcmp(threw, 'epsych:RunExpt:NoProject'), ...
    'a stale .ecfg positional should raise NoProject (got "%s")', threw);
fprintf('PASS: a stale .ecfg launch fails with the right migration message\n');

% 8. Roster round trip + old-shape synthesis ----------------------------------
R2 = epsych.SubjectRoster(rosterFile);
m2 = R2.findMembership(s1, pid);
assert(m2.TimerPeriod == 0.02 && strcmp(m2.TimerStartFcn, 'ep_TimerFcn_Start'), ...
    'membership session fields must survive a reload');

oldFile = fullfile(root, 'oldshape.esub');
S = load(rosterFile, '-mat');
S.memberships = rmfield(S.memberships, ...
    intersect(fieldnames(S.memberships), epsych.SubjectRoster.SESSION_FIELDS));
save(oldFile, '-struct', 'S', '-mat');
Rold = epsych.SubjectRoster(oldFile);
mo = Rold.findMembership(s1, pid);
assert(strcmp(mo.SavingFcn, '') && isnan(mo.TimerPeriod), ...
    'an old-shape membership should read as all-inherit');
fprintf('PASS: round trip, and an old-shape roster reads as all-inherit\n');

% 9. Shim absence --------------------------------------------------------------
assert(~ismethod(R, 'importFromConfig'), 'importFromConfig survived');
assert(~any(strcmp(methods('epsych.SubjectRoster'), 'legacyFile')), 'legacyFile survived');
assert(exist('ep_AddSubject', 'file') == 0, 'ep_AddSubject survived');
assert(exist('cl_AppetitiveDetection_BoxGUI', 'class') == 0 ...
    && exist('cl_AppetitiveDetection_BoxGUI', 'file') == 0, ...
    'cl_AppetitiveDetection_BoxGUI survived');
assert(exist('gui.BoxGUI', 'class') == 0, 'gui.BoxGUI survived');
fprintf('PASS: the deleted shims stay deleted\n');

epsych.SubjectRoster.setConfiguredFile('');
fprintf('ALL SESSION-WITHOUT-CONFIG SMOKE TESTS PASSED\n');
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
