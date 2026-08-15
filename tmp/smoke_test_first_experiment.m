function smoke_test_first_experiment
% smoke_test_first_experiment
% Exercises the examples/first_experiment tutorial end to end with no
% hardware and no human: an auto-clicker presses the RESPOND button
% whenever it arms. Unlike the detection-example smoke test, this drives
% the REAL runtime loop — ep_TimerFcn_Start / ep_TimerFcn_RunTime /
% ep_TimerFcn_Stop on a live timer — with FirstExperimentBoxGUI acting as
% the rig. Headless-safe (uifigure and timers work under -batch); runs in
% real time, expect roughly 15-30 s.
%
% Verifies:
%   1) create_first_protocol builds, compiles paired conditions, saves,
%      and reloads with the core trigger values seeded to 0
%   2) run_first_experiment completes NumTrials trials through the real
%      timer loop, driven only by GUI responses, then auto-stops and saves
%   3) outcomes are scored by the task contingency (go+press = Hit,
%      catch+press = FalseAlarm), RT_ms is recorded, and the
%      crash-recovery journal merged into the seed .mat
%   4) explore_first_data decodes the file and returns sane performance
%
% Run headless: matlab -batch "run('tmp/smoke_test_first_experiment.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'first_experiment'));

tmpdir = fullfile(tempdir, 'smoke_test_first_experiment');
if isfolder(tmpdir), rmdir(tmpdir, 's'); end
mkdir(tmpdir);
cleanup = onCleanup(@() cleanupAll(tmpdir));

% 1. Protocol builds, compiles, saves, reloads ---------------------------
% Short intervals so the real-time session below stays quick.
protFile = fullfile(tmpdir, 'FirstExperiment.eprot');
P = create_first_protocol(protFile, FlashDurs = [30 60], ...
    ITIRange = [120 220], RespWinDelay = 120, RespWinDur = 900);
assert(isfile(protFile), 'protocol file was not written');
assert(P.COMPILED.ntrials == 3, ...
    'expected 3 paired conditions (2 go + 1 catch), got %d', P.COMPILED.ntrials);
assert(all(ismember({'TrialType', 'FlashDur', 'ITI', 'RespWinDelay', 'RespWinDur'}, ...
    P.COMPILED.writeparams)), 'expected writeparams missing');

P2 = epsych.Protocol.load(protFile);
if P2.needsCompile, P2.compile(); end
assert(P2.COMPILED.ntrials == 3, 'reloaded protocol compiled %d trials', ...
    P2.COMPILED.ntrials);
fprintf('PASS: protocol create/compile/save/load\n');

% 2. Real-timer session driven by an auto-clicker ------------------------
dataPath = fullfile(tmpdir, 'data');
NTRIALS = 8;
[RUNTIME, GUI] = run_first_experiment(NumTrials = NTRIALS, ...
    ProtocolFile = protFile, DataPath = dataPath, ...
    SubjectName = 'SmokeTest', Test = true);

% The GUI plays the rig; the runtime polls its completion flag. Seeded 0,
% or the very first tick would misread the trial as complete.
assert(GUI.P.x_TrialComplete_1.Value == 0, ...
    'x_TrialComplete_1 must reload seeded to 0, got %g', ...
    GUI.P.x_TrialComplete_1.Value);

% Auto-clicker: press RESPOND whenever it arms. Every go trial becomes a
% Hit and every catch trial a FalseAlarm, which makes outcomes checkable.
watchdog = tic;
while strcmp(RUNTIME.TIMER.Running, 'on') && toc(watchdog) < 120
    pause(0.03) % timers fire during pause; this is the session's event pump
    if isvalid(GUI) && logical(GUI.RespondButton.Enable)
        GUI.respond();
    end
end
assert(strcmp(RUNTIME.TIMER.Running, 'off'), ...
    'session did not auto-stop within the watchdog window');
assert(numel(RUNTIME.TRIALS(1).DATA) == NTRIALS, ...
    'DATA has %d records, expected %d', numel(RUNTIME.TRIALS(1).DATA), NTRIALS);
fprintf('PASS: real-timer session auto-ran %d trials\n', NTRIALS);

% 3. Scoring, reaction times, and the two on-disk artifacts --------------
d = dir(fullfile(dataPath, 'SmokeTest', 'SmokeTest_*.mat'));
assert(isscalar(d), 'expected exactly one session file, found %d', numel(d));
datafile = fullfile(d(1).folder, d(1).name);
S = load(datafile);
assert(isfield(S, 'Data') && isfield(S, 'Info'), ...
    'session file must carry Data and Info variables');
assert(numel(S.Data) == NTRIALS, 'saved Data has %d records', numel(S.Data));

req = {'RespCode', 'RT_ms', 'InTrial', 'FlashDur', 'TrialType', 'ITI', ...
    'TrialIndex', 'TrialID', 'computerTimestamp', 'isTest'};
have = isfield(S.Data, req);
assert(all(have), 'missing DATA fields: %s', strjoin(req(~have), ', '));
assert(all([S.Data.isTest]), 'Test=true must mark every record as test data');

M = epsych.BitMask.decode(uint32([S.Data.RespCode]));
isGo = [S.Data.TrialType] == 0;
assert(all(M.Hit(isGo)) && ~any(M.Miss), ...
    'every go trial should be a Hit under the auto-clicker');
assert(all(M.FalseAlarm(~isGo)) && ~any(M.CorrectReject), ...
    'every catch trial should be a FalseAlarm under the auto-clicker');
assert(isequal(M.TrialType_0, isGo), 'TrialType bit disagrees with the dispatched TrialType');
rt = [S.Data.RT_ms];
assert(all(isfinite(rt)) && all(rt >= 0 & rt < 900), ...
    'RT_ms should be finite and inside the response window on every trial');
itis = [S.Data.ITI];
assert(numel(unique(itis)) > 1 && all(itis >= 120 & itis <= 220), ...
    'ITI should randomize within [120 220] every trial');

% Crash-recovery artifact: the journal must have merged into the seed .mat
% at stop, giving the info + data_NNNN layout.
seed = dir(fullfile(dataPath, 'RUNTIME_DATA_SmokeTest_Box_01_*.mat'));
assert(isscalar(seed), 'expected one crash-recovery seed file, found %d', numel(seed));
V = load(fullfile(seed(1).folder, seed(1).name));
assert(isfield(V, 'info') && isfield(V, sprintf('data_%04d', NTRIALS)), ...
    'journal was not merged into the recovery .mat');
fprintf('PASS: scoring, RTs, session file, journal merge\n');

% 4. GUI teardown and offline analysis -----------------------------------
fig = findall(groot, 'Type', 'figure', 'Tag', 'FirstExperimentBoxGUI');
assert(isscalar(fig), 'FirstExperimentBoxGUI figure not found');
assert(strcmp(GUI.ModeLabel.Text, 'Mode: Idle'), ...
    'mode label should end at Idle, got "%s"', GUI.ModeLabel.Text);
close(fig) % exercises closeGUI/teardown, including the rig timer
rig = timerfindall('Name', 'FirstExperimentBoxGUI_rig');
assert(isempty(rig), 'rig timer must not survive GUI teardown');

R = explore_first_data(datafile);
assert(R.nTrials == NTRIALS, 'analysis saw %d trials', R.nTrials);
assert(isequal(R.durations(:)', [30 60]), ...
    'unexpected flash durations: %s', mat2str(R.durations));
assert(all(R.hitRate == 1) && R.faRate == 1, ...
    'auto-clicker session should analyze as all-press behavior');
fprintf('PASS: GUI teardown + offline analysis\n');

fprintf('smoke_test_first_experiment: ALL PASS\n');
end


function cleanupAll(tmpdir)
close(findall(groot, 'Type', 'figure'));
t = timerfindall('Name', 'FirstExperimentTimer');
if ~isempty(t), stop(t); delete(t); end
t = timerfindall('Name', 'FirstExperimentBoxGUI_rig');
if ~isempty(t), stop(t); delete(t); end
if isfolder(tmpdir)
    try
        rmdir(tmpdir, 's');
    catch
    end
end
end
