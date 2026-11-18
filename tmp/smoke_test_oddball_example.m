function smoke_test_oddball_example
% smoke_test_oddball_example
% Exercises examples/oddball end to end with no hardware, no sound and no
% human. The session runs on the REAL timer loop (ep_TimerFcn_Start /
% RunTime / Stop) with OddballBehaviorGUI as the rig; a scripted responder
% answers deviants and standards by a fixed policy so all four outcomes
% occur and every one can be checked. Runs in real time, about 40-60 s.
% Silent: every session is started with PlayAudio=false.
%
% Verifies:
%   1) make_oddball_sounds writes both banks; create_oddball_protocol
%      compiles two conditions, keeps the banks out of the trial table, and
%      round-trips through save/load
%   2) OddballSelector, headless: runs of MinStandards..MaxStandards
%      standards each ending in one deviant; run lengths and both banks
%      block-balanced; a repeated selection is idempotent; a seed replays
%      the stream; a range edit and a bank edit take effect from the next
%      block without rewriting what was delivered; a TRIALS with no
%      TrialIndex (epsych.SelfTest's dry run) still selects
%   3) a live session: scoring matches the responder trial by trial, all
%      four outcomes occur, Pause holds the stream and Resume releases it,
%      a mid-session bank change reaches later standards, Stop ends and
%      saves; the file carries Data, Info (with the seed, pause, bank and
%      stop notes) and Sequences, and the journal merged
%   4) explore_oddball_data reproduces the counts and draws its figure
%   5) the Start gate holds a session until pressed, and a trial quota
%      auto-stops and saves
%   6) the GUI opens against a runtime with no session (epsych.SelfTest
%      check I6) without blocking at Start, and tears down cleanly
%
% Run headless: matlab -batch "run('tmp/smoke_test_oddball_example.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'oddball'));

tmpdir = fullfile(tempdir, 'smoke_test_oddball_example');
if isfolder(tmpdir), rmdir(tmpdir, 's'); end
mkdir(tmpdir);
cleanup = onCleanup(@() cleanupAll(tmpdir));

% 1. Sounds and protocol --------------------------------------------------
[stdF, devF] = make_oddball_sounds(fullfile(tmpdir, 'sounds'));
assert(numel(stdF) == 4 && numel(devF) == 3, 'expected 4 standards and 3 deviants')
assert(all(isfile(stdF)) && all(isfile(devF)), 'sound files were not written')
ai = audioinfo(char(devF(1)));
assert(abs(ai.Duration - 0.15) < 0.002 && ai.SampleRate == 44100, 'unexpected sound format')
d0 = dir(stdF(1));
make_oddball_sounds(fullfile(tmpdir, 'sounds')); % no Overwrite: files untouched
d1 = dir(stdF(1));
assert(isequal(d0.datenum, d1.datenum), 'an existing sound was rewritten without Overwrite')

protFile = fullfile(tmpdir, 'Oddball.eprot');
P = create_oddball_protocol(protFile, StandardFiles = stdF, DeviantFiles = devF, ...
    MinStandards = 1, MaxStandards = 3, ITIRange = [60 120], RespWinDelay = 0, RespWinDur = 300);
assert(P.COMPILED.ntrials == 2, 'expected 2 conditions, got %d', P.COMPILED.ntrials)
wp = P.COMPILED.writeparams;
assert(all(ismember({'TrialType', 'MinStandards', 'MaxStandards', 'ITI', 'RespWinDelay', 'RespWinDur'}, wp)), ...
    'expected trial-table columns missing')
assert(~any(ismember({'StandardFiles', 'DeviantFiles', 'StimFile', 'RespCode'}, wp)), ...
    'banks and read-backs must stay out of the trial table')

P2 = epsych.Protocol.load(protFile);
if P2.needsCompile, P2.compile(); end
pStd = P2.Interfaces(1).find_parameter('StandardFiles', includeInvisible = true);
assert(~pStd.Visible && isequal(OddballSelector.bankFiles(pStd), cellstr(stdF)), ...
    'standard bank did not round-trip through save/load')
pTC = P2.Interfaces(1).find_parameter('x_TrialComplete_1');
assert(isequal(pTC.Value, 0), 'x_TrialComplete_1 must reload seeded to 0')
fprintf('PASS: sounds, protocol compile/save/load\n');

% 2. Selector, headless ---------------------------------------------------
R = epsych.Runtime;
R.Interfaces = P2.Interfaces;
T = struct();
[T.parameters, T.trials, T.writeparams, T.writeParamIdx] = ...
    epsych.Runtime.compiledTrialColumns(P2.COMPILED);
ttCol = T.writeParamIdx.TrialType;
pStimFile = R.find_parameter('StimFile');

sel = OddballSelector;
sel.Seed = 11;
sel.initialize(T);
sel.setRuntime(R, 1);
N1 = 60;
plans = repmat(planTemplate(), 1, 0);
for k = 1:N1
    T.TrialIndex = k;
    id = sel.selectNext(T);
    plans(k) = sel.LastPlan;
    assert((T.trials{id, ttCol} == 0) == plans(k).IsDeviant, 'trial %d: row disagrees with the plan', k)
    assert(strcmp(char(pStimFile.Value), plans(k).StimFile), ...
        'trial %d: StimFile was not written for the trial', k)
end
checkRunStructure([plans.RunLength], [plans.RunPosition], [plans.IsDeviant]);
runLens = [plans([plans.IsDeviant]).RunLength];
checkBlocks(runLens, 1:3, 'run lengths');
checkBlocks(string({plans(~[plans.IsDeviant]).StimFile}), stdF, 'standard files');
checkBlocks(string({plans([plans.IsDeviant]).StimFile}), devF, 'deviant files');

T.TrialIndex = N1;
idAgain = sel.selectNext(T);
assert(isequal(sel.LastPlan, plans(N1)) && (T.trials{idAgain, ttCol} == 0) == plans(N1).IsDeviant, ...
    'a repeated selection of the same trial must return the same decision')

sel2 = OddballSelector;
sel2.Seed = 11;
sel2.initialize(T);
sel2.setRuntime(R, 1);
for k = 1:N1
    T.TrialIndex = k;
    sel2.selectNext(T);
    assert(isequal(sel2.LastPlan, plans(k)), 'seed %d did not replay trial %d', sel2.Seed, k)
end

% Edit the range to 1..5 and shrink the standard bank mid-stream.
T.trials(:, T.writeParamIdx.MaxStandards) = {5};
pStdLive = R.find_parameter('StandardFiles', includeInvisible = true);
pStdLive.Value = cellstr(stdF(1:2));
N2 = 160;
for k = N1+1:N2
    T.TrialIndex = k;
    sel.selectNext(T);
    plans(k) = sel.LastPlan;
end
checkRunStructure([plans.RunLength], [plans.RunPosition], [plans.IsDeviant]);
for k = 1:N1
    pk = sel.preview(k);
    assert(isequal(pk.StimFile, plans(k).StimFile) && pk.RunLength == plans(k).RunLength, ...
        'the edits rewrote delivered trial %d', k)
end
lateRuns = [plans(N1+1:end).RunLength];
assert(all(lateRuns <= 5) && any(lateRuns > 3), ...
    'the widened range (1..5) never took effect: %s', mat2str(unique(lateRuns)))
isStd = ~[plans.IsDeviant];
lateStd = string({plans(isStd & (1:N2) > N1 + 20).StimFile});
assert(~isempty(lateStd) && all(ismember(lateStd, stdF(1:2))), ...
    'standards after the bank edit still drew from the old bank')

% epsych.SelfTest hands the same snapshot, with no TrialIndex, again and again.
Tst = rmfield(T, 'TrialIndex');
sel3 = OddballSelector;
sel3.initialize(Tst);
ids = arrayfun(@(~) sel3.selectNext(Tst), 1:20);
assert(all(ismember(ids, 1:2)) && numel(unique(ids)) == 2, ...
    'a selector with no runtime and no TrialIndex must still select both kinds')
sel3.setRuntime(epsych.Runtime, 1);
sel3.onComplete(1, struct('TrialIndex', 1));
sel3.onRecompile(Tst);
fprintf('PASS: selector run structure, block balance, idempotence, seed replay, live edits\n');

% 3. Live session ---------------------------------------------------------
dataPath = fullfile(tmpdir, 'data');
[RUNTIME, GUI] = run_oddball_experiment(ProtocolFile = protFile, DataPath = dataPath, ...
    SubjectName = 'SmokeTest', Test = true, WaitForBegin = false, PlayAudio = false);
assert(GUI.IsStarted && ~GUI.IsPaused, 'session should be running after the run-mode broadcast')
assert(contains(GUI.StatusLabel.Text, 'Preview'), 'a Test session should say Preview')

% The responder and the scripted steps run from a timer (OddballSessionDriver);
% this function only waits on its Done flag. Reading RUNTIME.TRIALS from
% here while the session timer writes it corrupts R2024b's heap -- see the
% driver's help.
drv = OddballSessionDriver(RUNTIME, GUI, stdF);
watchdog = tic;
while ~drv.Done && toc(watchdog) < 150
    pause(0.05) % timers fire during pause; this is the session's event pump
end
if ~isempty(drv.Error), rethrow(drv.Error); end
assert(drv.Done, 'the scripted session did not finish within 150 s')
paused = drv.Paused; resumed = drv.Resumed; banked = drv.Banked; stopped = drv.Stopped;
heldCounts = drv.HeldCounts; bankedAt = drv.BankedAt; decided = drv.Decided;
delete(drv)
assert(paused && resumed && banked && stopped, 'the session did not reach every scripted step')
assert(strcmp(RUNTIME.TIMER.Running, 'off'), 'Stop did not stop the session timer')
assert(heldCounts(2) == heldCounts(1), ...
    'trials kept completing during the pause (%d then %d)', heldCounts(1), heldCounts(2))
assert(GUI.IsStopped && ~logical(GUI.PauseButton.Enable) && ~logical(GUI.StopButton.Enable), ...
    'the GUI should stand down after Stop')

d = dir(fullfile(dataPath, 'SmokeTest', 'SmokeTest_*.mat'));
assert(isscalar(d), 'expected one session file, found %d', numel(d));
datafile = fullfile(d.folder, d.name);
S = load(datafile);
assert(all(isfield(S, {'Data', 'Info', 'Sequences'})), 'session file must carry Data, Info and Sequences')
D = S.Data;
n = numel(D);
assert(n >= 40 && n <= 41, 'expected 40-41 trials at Stop, saved %d', n)
assert(all([D.isTest]), 'Test=true must mark every record')

M = epsych.BitMask.decode(uint32([D.RespCode]));
isDevD = [D.TrialType] == 0;
assert(isequal(M.TrialType_0, isDevD) && isequal(M.TrialType_1, ~isDevD), ...
    'TrialType bits disagree with the dispatched TrialType')
% A press counts only inside the window. Under load the rig timer can notice
% the window's end late, so a press the responder made may arrive after it:
% that press must be scored as withheld, never as a response.
pressed = decided(1:n) == 1;
rt = [D.RT_ms];
resp = rt >= 0;   % what the GUI registered
assert(~any(resp & ~pressed), 'a response was registered on a trial nobody pressed')
assert(nnz(pressed & ~resp) <= 3, '%d presses were refused as late; the responder should rarely be', ...
    nnz(pressed & ~resp))
assert(isequal(M.Hit,           isDevD & resp),  'Hit scoring is wrong')
assert(isequal(M.Miss,          isDevD & ~resp), 'Miss scoring is wrong')
assert(isequal(M.FalseAlarm,   ~isDevD & resp),  'False-alarm scoring is wrong')
assert(isequal(M.CorrectReject,~isDevD & ~resp), 'Correct-reject scoring is wrong')
assert(all([nnz(M.Hit) nnz(M.Miss) nnz(M.FalseAlarm) nnz(M.CorrectReject)] > 0), ...
    'all four outcomes should occur under the responder policy')
assert(all(rt(resp) < 300) && all(rt(~resp) == -1), ...
    'RT_ms must fall inside the window when answered and be -1 otherwise')
iti = [D.ITI];
assert(all(iti >= 60 & iti <= 120) && numel(unique(iti)) > 1, 'ITI should redraw within [60 120]')

checkRunStructure([D.RunLength], [D.RunPosition], isDevD);
checkBlocks([D(isDevD).RunLength], 1:3, 'session run lengths');
assert(all(ismember(string({D(isDevD).StimFile}), devF)), 'a deviant played a file outside its bank')
stdPlayed = string({D(~isDevD).StimFile});
assert(all(ismember(stdPlayed, stdF)), 'a standard played a file outside its bank')
lateStdLive = string({D(~isDevD & (1:n) >= bankedAt + 8).StimFile});
assert(~isempty(lateStdLive) && all(ismember(lateStdLive, stdF(1:2))), ...
    'standards well after the bank change still drew from the old bank')

notes = string(S.Info.NotesText);
for want = ["sequence seeds", "paused", "resumed", "Standard sounds set to 2 file(s)", "stopped"]
    assert(contains(notes, want), 'session notes lack "%s"', want)
end
assert(~isempty(S.Sequences.RunLength) && ~isempty(S.Sequences.Standards) ...
    && ~isempty(S.Sequences.Deviants), 'the sequences were not saved')

seed = dir(fullfile(dataPath, 'RUNTIME_DATA_SmokeTest_Box_01_*.mat'));
assert(isscalar(seed), 'expected one crash-recovery seed file, found %d', numel(seed));
V = load(fullfile(seed.folder, seed.name));
assert(isfield(V, 'info') && isfield(V, sprintf('data_%04d', n)), ...
    'journal was not merged into the recovery .mat')
fprintf('PASS: live session (%d trials): scoring, pause/resume, bank change, stop, save\n', n);

% 4. Offline analysis -----------------------------------------------------
before = findall(groot, 'Type', 'figure');
A = explore_oddball_data(datafile);
assert(A.nTrials == n && A.counts.Hit == nnz(M.Hit) && A.counts.FalseAlarm == nnz(M.FalseAlarm), ...
    'analysis counts disagree with the decoded file')
assert(abs(A.hitRate - nnz(M.Hit)/nnz(isDevD)) < 1e-12, 'analysis hit rate is wrong')
newFigs = setdiff(findall(groot, 'Type', 'figure'), before);
assert(~isempty(newFigs), 'explore_oddball_data drew no figure')
delete(newFigs)
fprintf('PASS: offline analysis\n');

% 5. Start gate and trial quota -------------------------------------------
fig = findall(groot, 'Type', 'figure', 'Tag', 'OddballBehaviorGUI');
close(fig) % the next GUI would close it anyway (single instance)
assert(isempty(timerfindall('Name', 'OddballBehaviorGUI_rig')), 'rig timer survived teardown')

dataPath2 = fullfile(tmpdir, 'data2');
% Retries until the gate opens: the GUI may not exist yet at the first try,
% and a missed press would hold the session -- and this test -- forever.
presser = timer(Name = 'OddballStartPresser', StartDelay = 1.5, Period = 0.25, ExecutionMode = 'fixedSpacing', ...
    TimerFcn = @(t,~) pressStart(t));
start(presser);
tStart = tic;
[RUNTIME2, GUI2] = run_oddball_experiment(ProtocolFile = protFile, DataPath = dataPath2, ...
    SubjectName = 'GateTest', Test = true, WaitForBegin = true, PlayAudio = false, NumTrials = 5);
assert(toc(tStart) >= 1.4, 'the session did not hold at Start')
assert(GUI2.Gate.Released, 'the Start gate should be released')
delete(presser)
watchdog = tic;
while strcmp(RUNTIME2.TIMER.Running, 'on') && toc(watchdog) < 60
    pause(0.05)
end
assert(strcmp(RUNTIME2.TIMER.Running, 'off'), 'the quota did not stop the session')
d2 = dir(fullfile(dataPath2, 'GateTest', 'GateTest_*.mat'));
assert(isscalar(d2), 'the quota run saved no file')
S2 = load(fullfile(d2.folder, d2.name), 'Data');
assert(numel(S2.Data) == 5, 'quota run saved %d trials, expected 5', numel(S2.Data))
close(findall(groot, 'Type', 'figure', 'Tag', 'OddballBehaviorGUI'))
fprintf('PASS: Start gate holds, quota auto-stops and saves\n');

% 6. A runtime with no session (epsych.SelfTest check I6) -----------------
rt = epsych.Runtime;
rt.EVENTS = epsych.EventHub;
tOpen = tic;
G = OddballBehaviorGUI(rt); % default WaitForBegin=true must not block here
assert(toc(tOpen) < 20 && isvalid(G) && isvalid(G.h_figure), 'GUI did not open against an empty runtime')
G.pauseSession(); G.stopSession(Confirm = false); G.respond(); % all inert
close(G.h_figure)
assert(isempty(timerfindall('Name', 'OddballBehaviorGUI_rig')), 'rig timer survived teardown')
fprintf('PASS: GUI against an empty runtime\n');

fprintf('smoke_test_oddball_example: ALL PASS\n');
end


function p = planTemplate()
p = struct('TrialIndex', 0, 'Run', 0, 'RunLength', 0, 'RunPosition', 0, ...
    'IsDeviant', false, 'Ordinal', 0, 'StimFile', '', 'StimID', 0);
end


function checkRunStructure(runLen, runPos, isDev)
% Runs are consecutive: positions count 1..L then the deviant at L+1, and
% the next trial starts a new run at position 1.
assert(isequal(isDev, runPos == runLen + 1), 'a deviant is not where its run ends')
for k = 2:numel(runPos)
    if isDev(k-1)
        assert(runPos(k) == 1, 'trial %d should open a new run', k)
    else
        assert(runPos(k) == runPos(k-1) + 1 && runLen(k) == runLen(k-1), ...
            'trial %d breaks its run', k)
    end
end
end


function checkBlocks(seq, pool, label)
% Block randomization: every complete block of numel(pool) draws is a
% permutation of the pool.
B = numel(pool);
nFull = floor(numel(seq) / B);
assert(nFull >= 2, '%s: too few draws (%d) to check blocks', label, numel(seq))
for b = 1:nFull
    blk = seq((b-1)*B + (1:B));
    assert(isequal(sort(blk), sort(pool(:).')), '%s: block %d is not a permutation: %s', ...
        label, b, strjoin(string(blk), ', '))
end
end


function pressStart(t)
% What an operator's click on Start does, from a timer: the driver is
% blocked inside the GUI's constructor until the gate opens.
f = findall(groot, 'Type', 'figure', 'Tag', 'OddballBehaviorGUI');
if isempty(f) || ~isa(f(1).UserData, 'OddballBehaviorGUI'), return; end
G = f(1).UserData;
if isempty(G.Gate) || ~isvalid(G.Gate), return; end
G.startSession();
if G.Gate.Released, stop(t); end
end


function cleanupAll(tmpdir)
close(findall(groot, 'Type', 'figure'));
for name = ["OddballTimer", "OddballBehaviorGUI_rig", "OddballStartPresser", "OddballSessionDriver"]
    t = timerfindall('Name', name);
    if ~isempty(t), stop(t); delete(t); end
end
if isfolder(tmpdir)
    try
        rmdir(tmpdir, 's');
    catch
    end
end
end
