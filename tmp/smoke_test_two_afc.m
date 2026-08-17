function smoke_test_two_afc
% smoke_test_two_afc
% Exercises the examples/two_afc tutorial end to end with no hardware and
% no human: a scripted observer answers each trial through the GUI's
% respondSide method, and every fourth trial is deliberately left
% unanswered so the abort path is covered too. Drives the REAL runtime
% loop (ep_TimerFcn_Start / RunTime / Stop on a live timer) with
% TwoAFCBehaviorGUI acting as the rig. Headless-safe; runs in real time,
% expect roughly 30-60 s.
%
% Verifies:
%   1) create_2afc_protocol crosses side x contrast (not pairs them),
%      compiles, saves, reloads, and seeds the core triggers to 0
%   2) run_2afc_experiment completes NumTrials trials through the real
%      timer loop, driven only by GUI responses, then auto-stops and saves
%   3) the 2AFC bit encoding: Choice_* records the side chosen, the
%      detection outcome bits are recast with LEFT as the yes-response
%      (Hit on TrialType_0, CorrectReject on TrialType_1), unanswered
%      trials are Abort with no Choice bit, and RT/ChoiceSide agree
%   4) psychophysics.SessionMetrics scores the session with its DEFAULT
%      trial types — the whole point of that mapping — and its percent
%      correct matches a hand count
%   5) explore_2afc_data decodes the file, fits the choice curve, and
%      recovers the injected side bias
%
% Run headless: matlab -batch "run('tmp/smoke_test_two_afc.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'two_afc'));

tmpdir = fullfile(tempdir, 'smoke_test_two_afc');
if isfolder(tmpdir), rmdir(tmpdir, 's'); end
mkdir(tmpdir);
cleanup = onCleanup(@() cleanupAll(tmpdir));

% 1. Protocol builds, crosses, saves, reloads ----------------------------
% Short intervals so the real-time session below stays quick.
protFile = fullfile(tmpdir, 'TwoAFC.eprot');
P = create_2afc_protocol(protFile, Contrasts = [0.04 0.08 0.16 0.32], ...
    ITIRange = [100 200], FlashDur = 80, RespWinDur = 600);
assert(isfile(protFile), 'protocol file was not written');
assert(P.COMPILED.ntrials == 8, ...
    'expected 2 sides x 4 contrasts = 8 crossed conditions, got %d', P.COMPILED.ntrials);
assert(all(ismember({'TrialType', 'Contrast', 'BaseLevel', 'FlashDur', ...
    'RespWinDur', 'ITI'}, P.COMPILED.writeparams)), 'expected writeparams missing');

% The cross must produce every side at every contrast; pairing would give 2.
idx = struct;
for k = 1:numel(P.COMPILED.writeparams)
    idx.(P.COMPILED.writeparams{k}) = k;
end
combos = unique([cell2mat(P.COMPILED.trials(:, idx.TrialType)), ...
    cell2mat(P.COMPILED.trials(:, idx.Contrast))], 'rows');
assert(size(combos, 1) == 8, 'conditions are not fully crossed: %s', mat2str(combos));

P2 = epsych.Protocol.load(protFile);
if P2.needsCompile, P2.compile(); end
assert(P2.COMPILED.ntrials == 8, 'reloaded protocol compiled %d trials', P2.COMPILED.ntrials);
fprintf('PASS: protocol crosses side x contrast, saves and reloads\n');

% 2. Real-timer session driven by a scripted observer --------------------
% The observer answers from a cumulative Gaussian with a KNOWN leftward
% bias, so section 5 can check that the choice-curve fit recovers it.
rng(0);
PSE_TRUE = 0.10;  % positive = needs rightward evidence = biased toward LEFT
SIGMA    = 0.06;
dataPath = fullfile(tmpdir, 'data');
NTRIALS = 48;
[RUNTIME, GUI] = run_2afc_experiment(NumTrials = NTRIALS, ...
    ProtocolFile = protFile, DataPath = dataPath, ...
    SubjectName = 'SmokeTest', Test = true);

assert(GUI.P.x_TrialComplete_1.Value == 0, ...
    'x_TrialComplete_1 must reload seeded to 0, got %g', GUI.P.x_TrialComplete_1.Value);

% Scripted observer: choose right with probability normcdf((signed -
% PSE_TRUE)/SIGMA), i.e. a real psychometric observer carrying a leftward
% bias; and stay silent on every 8th trial so the abort path is covered.
answeredTrials = 0;
watchdog = tic;
while strcmp(RUNTIME.TIMER.Running, 'on') && toc(watchdog) < 300
    pause(0.02) % timers fire during pause; this is the session's event pump
    if ~isvalid(GUI) || ~logical(GUI.LeftButton.Enable), continue; end
    T = RUNTIME.TRIALS(1);
    if mod(T.TrialIndex, 8) == 0
        continue % let the response window lapse -> Abort
    end
    correctSide = T.trials{T.NextTrialID, T.writeParamIdx.TrialType};
    contrast    = T.trials{T.NextTrialID, T.writeParamIdx.Contrast};
    signed = contrast * (2 * correctSide - 1);
    GUI.respondSide(double(rand < normcdf((signed - PSE_TRUE) / SIGMA)));
    answeredTrials = answeredTrials + 1;
end
assert(strcmp(RUNTIME.TIMER.Running, 'off'), ...
    'session did not auto-stop within the watchdog window');
assert(numel(RUNTIME.TRIALS(1).DATA) == NTRIALS, ...
    'DATA has %d records, expected %d', numel(RUNTIME.TRIALS(1).DATA), NTRIALS);
fprintf('PASS: real-timer session auto-ran %d trials (%d answered)\n', ...
    NTRIALS, answeredTrials);

% 3. The 2AFC encoding ---------------------------------------------------
d = dir(fullfile(dataPath, 'SmokeTest', 'SmokeTest_*.mat'));
assert(isscalar(d), 'expected exactly one session file, found %d', numel(d));
datafile = fullfile(d(1).folder, d(1).name);
S = load(datafile);
assert(isfield(S, 'Data') && isfield(S, 'Info'), ...
    'session file must carry Data and Info variables');

req = {'RespCode', 'ChoiceSide', 'RT_ms', 'SignedContrast', 'InTrial', 'TrialType', ...
    'Contrast', 'BaseLevel', 'ITI', 'TrialIndex', 'TrialID', 'computerTimestamp', 'isTest'};
have = isfield(S.Data, req);
assert(all(have), 'missing DATA fields: %s', strjoin(req(~have), ', '));

M = epsych.BitMask.decode(uint32([S.Data.RespCode]));
choice   = [S.Data.ChoiceSide];
side     = [S.Data.TrialType];
answered = choice >= 0;

% SignedContrast is a stimulus fact, recorded on every trial regardless of
% whether it was answered: negative = left brighter (left correct).
signedContrast = [S.Data.SignedContrast];
assert(isequal(signedContrast, [S.Data.Contrast] .* (2 * side - 1)), ...
    'SignedContrast must equal Contrast signed by which side was correct');

% Aborts: no answer, no Choice bit, no outcome bit, sentinel RT. The
% sentinel is -1 and not NaN because hw.Parameter.clamp_value_ applies
% max(value, Min), which drops NaN and stores Min instead.
assert(isequal(M.Abort, ~answered), 'Abort must mark exactly the unanswered trials');
assert(~any(M.Abort & (M.Choice_0 | M.Choice_1)), 'an aborted trial must carry no Choice bit');
assert(~any(M.Abort & (M.Hit | M.Miss | M.CorrectReject | M.FalseAlarm)), ...
    'an aborted trial must carry no outcome bit');
assert(all([S.Data(M.Abort).RT_ms] == -1) && all(choice(~answered) == -1), ...
    'aborted trials must carry the -1 sentinel in RT_ms and ChoiceSide');
assert(any(M.Abort), 'the observer should have aborted at least one trial');

% Choice bits record the side chosen, independent of correctness.
assert(isequal(M.Choice_1(answered), choice(answered) == 1), ...
    'Choice_1 must mark exactly the rightward choices');
assert(isequal(M.Choice_0(answered), choice(answered) == 0), ...
    'Choice_0 must mark exactly the leftward choices');

% Outcome bits recast with LEFT as the yes-response.
correct = choice == side;
assert(isequal(M.Hit,           answered & correct  & side == 0), 'Hit mapping wrong');
assert(isequal(M.Miss,          answered & ~correct & side == 0), 'Miss mapping wrong');
assert(isequal(M.CorrectReject, answered & correct  & side == 1), 'CorrectReject mapping wrong');
assert(isequal(M.FalseAlarm,    answered & ~correct & side == 1), 'FalseAlarm mapping wrong');
assert(isequal(M.TrialType_0, side == 0) && isequal(M.TrialType_1, side == 1), ...
    'TrialType bits disagree with the dispatched TrialType');
assert(all(M.Reward(answered) == correct(answered)), 'Reward must follow correctness');
assert(all(M.Punish(answered) == ~correct(answered)), 'Punish must follow incorrectness');

rt = [S.Data.RT_ms];
assert(all(isfinite(rt(answered)) & rt(answered) >= 0 & rt(answered) < 600), ...
    'answered trials need a real RT inside the response window');
assert(~any(isnan([S.Data.RT_ms])) && ~any(isnan(choice)), ...
    'a parameter can never hold NaN; the examples use -1 as the missing marker');
fprintf('PASS: 2AFC bit encoding (choice, outcome, abort, contingency)\n');

% 4. The toolbox scores it with DEFAULT trial types ----------------------
SM = psychophysics.SessionMetrics(S.Data);
handCount = sum(correct & answered) / sum(answered);
assert(abs(SM.Results.Rate.Correct - handCount) < 1e-9, ...
    'SessionMetrics percent correct (%.4f) disagrees with a hand count (%.4f)', ...
    SM.Results.Rate.Correct, handCount);
assert(SM.Results.N.Abort == sum(~answered), 'SessionMetrics abort count disagrees');
assert(isfinite(SM.Results.DPrime) && isfinite(SM.Results.Criterion), ...
    'd'' and criterion must be finite with the infCorrection applied');
fprintf('PASS: SessionMetrics with defaults (%.0f%% correct, d''=%.2f, c=%.2f)\n', ...
    100 * SM.Results.Rate.Correct, SM.Results.DPrime, SM.Results.Criterion);

% 5. GUI teardown and offline analysis -----------------------------------
fig = findall(groot, 'Type', 'figure', 'Tag', 'TwoAFCBehaviorGUI');
assert(isscalar(fig), 'TwoAFCBehaviorGUI figure not found');
assert(strcmp(GUI.ModeLabel.Text, 'Mode: Idle'), ...
    'mode label should end at Idle, got "%s"', GUI.ModeLabel.Text);
assert(~isempty(GUI.ChoiceTable.Data), 'choice table never populated');
close(fig) % exercises closeGUI/teardown, including the rig timer
assert(isempty(timerfindall('Name', 'TwoAFCBehaviorGUI_rig')), ...
    'rig timer must not survive GUI teardown');

R = explore_2afc_data(datafile);
assert(R.nTrials == NTRIALS, 'analysis saw %d trials', R.nTrials);
assert(R.nAborted == sum(~answered), 'analysis abort count disagrees');
assert(isequal(R.contrasts(:)', [0.04 0.08 0.16 0.32]), ...
    'unexpected contrasts: %s', mat2str(R.contrasts));
assert(numel(R.signedLevels) == 8, 'expected 8 signed levels, got %d', numel(R.signedLevels));

% The choice-curve fit must converge and recover the injected bias: the
% observer answered around a PSE of +0.10, i.e. leaning LEFT. Accuracy at
% the easiest contrast must also beat the hardest.
assert(isfinite(R.pse) && isfinite(R.jnd) && R.jnd > 0, ...
    'choice-curve fit did not converge (pse %g, jnd %g)', R.pse, R.jnd);
assert(abs(R.pse - PSE_TRUE) < 0.12, ...
    'fitted PSE %+.3f is far from the injected %+.3f', R.pse, PSE_TRUE);
assert(R.criterion < 0, ...
    'criterion should be negative for a leftward bias, got %.2f', R.criterion);
assert(R.accuracy(end) >= R.accuracy(1), ...
    'accuracy should not fall from the hardest to the easiest contrast');
fprintf('PASS: GUI teardown + offline analysis (PSE %+.3f, JND %.3f, c %.2f)\n', ...
    R.pse, R.jnd, R.criterion);

fprintf('smoke_test_two_afc: ALL PASS\n');
end


function cleanupAll(tmpdir)
close(findall(groot, 'Type', 'figure'));
for nm = {'TwoAFCTimer', 'TwoAFCBehaviorGUI_rig'}
    t = timerfindall('Name', nm{1});
    if ~isempty(t), stop(t); delete(t); end
end
if isfolder(tmpdir)
    try
        rmdir(tmpdir, 's');
    catch
    end
end
end
