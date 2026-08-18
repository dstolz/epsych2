% smoke_test_pump_trial_cycle.m
% Headless regression test for the syringe-pump example under a REAL session
% loop — no pump required.
%
% Reproduces what a RunExpt session does rather than what run_pump_session
% does: the runtime writes the reward, polls x_TrialComplete_1, and does
% nothing else. Two failures used to hide behind that, and both are checked
% here:
%
%   1. An unwritten trigger reads back EMPTY, and `if ~[]` is FALSE, so
%      ep_TimerFcn_RunTime completed a trial on every tick — the session ran
%      through its trials ballistically, at the timer period.
%   2. Nothing ever pulsed the pump's Start: run_pump_session does that in
%      its own loop, and a RunExpt session has no such loop. The pump was
%      loaded with a reward it never dispensed.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_pump_trial_cycle.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile
% leaves behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.SyringePump', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'examples', 'syringepump'));

fprintf('\n=== Syringe Pump Trial Cycle Smoke Test ===\n\n');
results = {};

ITI_SEC = 0.4;     % short enough for a quick test, long enough to time
NTRIALS = 4;

RUNTIME = [];
pump = [];
behaviorGUI = [];

%% Session scaffold: what RunExpt + ep_TimerFcn_Start build
try
    [P, pump] = create_pump_protocol('', Save = false);
    pump.SimAutoStop = true;   % model the motor, so Status settles on its own

    RUNTIME = epsych.Runtime;
    RUNTIME.isTest = true;
    RUNTIME.EVENTS = epsych.EventHub;
    RUNTIME.Interfaces = P.Interfaces;

    % The ITI is what the pacing assertions are about, so pin it rather than
    % letting isRandom redraw 2-4 s per trial. Recompiled, because the trial
    % table the protocol arrived with still carries the authored interval.
    itiParam = RUNTIME.find_parameter('ITI');
    itiParam(1).isRandom = false;
    itiParam(1).Min = 0;
    itiParam(1).Values = {ITI_SEC};
    itiParam(1).Value = ITI_SEC;
    P.compile();

    subject = epsych.DefaultSubject(struct('Name', 'PumpCycle', ...
        'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));

    C = P.COMPILED;
    T = struct;
    T.protocol    = P;
    T.Subject     = subject;
    T.BoxID       = subject.BoxID;
    [T.parameters, T.trials, T.writeparams, T.writeParamIdx] = ...
        epsych.Runtime.compiledTrialColumns(C);
    T.selector = epsych.TrialSelector.create(struct('trialFunc', C.OPTIONS.trialFunc));
    T.selector.initialize(T);
    T.FORCE_TRIAL         = false;
    T.RECOMPILE_REQUESTED = false;
    T.DataFilename        = '';
    T.TrialIndex          = 1;
    T.NextTrialID         = T.selector.selectNext(T);
    T.selector.setRuntime(RUNTIME, 1);
    % No DATA field: ep_TimerFcn_RunTime creates it on the first trial, the
    % same way it does over the struct ep_TimerFcn_Start builds.

    % ep_TimerFcn_RunTime journals every completed trial, so give it the
    % same seed .mat + .epj pair ep_TimerFcn_Start would have made.
    seed = [tempname '.mat'];
    info = struct('Subject', subject, 'CompStartTimestamp', datetime('now'));
    save(seed, 'info', '-v6');
    RUNTIME.DataFile(1) = seed;
    RUNTIME.Journal = epsych.TrialJournal(regexprep(seed, '\.mat$', '.epj'), ...
        FallbackMatFile = seed);

    RUNTIME.TRIALS = T;  % the setter resolves the triggers and dispatches trial 1

    results(end+1,:) = check('Session scaffold built', true);
catch ME
    results(end+1,:) = check(['Scaffold: ' ME.message], false);
    reportAndExit(results);
    return
end

%% 1. The completion trigger is a number the runtime can test
% add_parameter fills Values, not Value, so a protocol built in code (or
% reloaded from one) arrives with an EMPTY Value.
% epsych.Runtime.resolveTriggerParameters seeds it.
try
    tc = RUNTIME.find_parameter('x_TrialComplete_1', includeTriggers = true, ...
        includeInvisible = true);
    results(end+1,:) = check('TrialComplete resolves to one parameter', isscalar(tc));
    results(end+1,:) = check('It holds a testable scalar, not []', ...
        isnumeric(tc(1).Value) && isscalar(tc(1).Value));
    results(end+1,:) = check('It starts low', tc(1).Value == 0);
catch ME
    results(end+1,:) = check(['Trigger seeding: ' ME.message], false);
end

%% 2. An unreadable completion flag never advances a trial
% The ballistic bug in one assertion: with the flag empty, twenty ticks must
% do nothing at all. `if ~[]` is false, so testing the value alone fell
% through and completed a trial on every one of them.
try
    tc = RUNTIME.find_parameter('x_TrialComplete_1', includeTriggers = true, ...
        includeInvisible = true);
    for bad = {[], 0}
        tc(1).Value = bad{1};
        before = RUNTIME.TRIALS(1).TrialIndex;
        for k = 1:20
            RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
        end
        results(end+1,:) = check( ...
            sprintf('20 ticks advance nothing while the flag reads %s', ...
            mat2str(bad{1})), RUNTIME.TRIALS(1).TrialIndex == before);
    end
    tc(1).Value = 0;
catch ME
    results(end+1,:) = check(['Ballistic guard: ' ME.message], false);
end

%% 2b. Neither does a flag that cannot be read back at all
% The hardware version of the same hazard: a parameter that will not read
% answers NaN (hw.Parameter.get.Value), which has no truth value either. It
% has to come from a READ — assigning NaN to a parameter only clamps it to
% the bound, so the empty case above is the only one a software rig reaches.
% Few ticks, because every one of them logs the refused read.
try
    unreadable = RUNTIME.TRIALS(1).protocol.SoftwareModule.add_parameter( ...
        'x_Unreadable_1', 0, isTrigger = true, Access = 'Write');
    saved = RUNTIME.TRIGGERS(1).TrialComplete;
    RUNTIME.TRIGGERS(1).TrialComplete = unreadable;

    results(end+1,:) = check('An unreadable parameter reads back NaN', ...
        isnan(unreadable.Value));

    before = RUNTIME.TRIALS(1).TrialIndex;
    for k = 1:3
        RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
    end
    results(end+1,:) = check('Ticks advance nothing while the flag reads NaN', ...
        RUNTIME.TRIALS(1).TrialIndex == before);

    RUNTIME.TRIGGERS(1).TrialComplete = saved;
catch ME
    results(end+1,:) = check(['Unreadable flag: ' ME.message], false);
end

%% 3. The GUI runs the trial cycle: pump pulsed, trials paced by the ITI
try
    behaviorGUI = PumpBehaviorGUI(RUNTIME, WaitForBegin = false);
    startInfused = pump.get_parameter('VolumeInfused');
    firstIdx = RUNTIME.TRIALS(1).TrialIndex;

    % Record is what starts trial 1's timeline: it was dispatched inside the
    % TRIALS setter, before this window existed to hear NewTrial.
    RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Record));

    % Stand in for the PsychTimer. Wall-clock bounded so a stalled cycle
    % fails the test instead of hanging it.
    tStart = tic;
    stamps = nan(1, NTRIALS);
    done = 0;
    while done < NTRIALS && toc(tStart) < 60
        before = RUNTIME.TRIALS(1).TrialIndex;
        RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
        if RUNTIME.TRIALS(1).TrialIndex > before
            done = done + 1;
            stamps(done) = toc(tStart);
        end
        pause(0.02)     % lets the GUI's rig timer and the pump panel run
    end
    stamps = stamps(1:done);

    D = RUNTIME.TRIALS(1).DATA(firstIdx:end);
    results(end+1,:) = check('Every trial completed', done == NTRIALS);
    results(end+1,:) = check('Each one produced a DATA record', numel(D) == NTRIALS);

    % The bug: trials completing at the timer period rather than one per
    % dispense-plus-ITI. Every gap has to clear the ITI and the reward it
    % delivered, and none may drag on far past them.
    gaps = diff(stamps);
    results(end+1,:) = check('Trials are paced, not ballistic', ...
        ~isempty(gaps) && all(gaps > ITI_SEC));
    results(end+1,:) = check('No trial stalled', ...
        ~isempty(gaps) && all(gaps < 8));

    % The other bug: nothing pulsed Start, so nothing was ever dispensed.
    infused = [D.VolumeInfused];
    results(end+1,:) = check('The pump actually dispensed', ...
        infused(end) > startInfused);
    results(end+1,:) = check('One reward per trial, at the dispatched size', ...
        all(abs(diff([startInfused infused]) - [D.Volume]) < 1e-9));

    % Ending the session mid-dispense — which is where this loop leaves it,
    % the runtime having already dispatched the next reward — must not leave
    % the pusher advancing.
    RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Stop));
    drawnow
    results(end+1,:) = check('Ending the session stops the pump', ...
        ~ismember(pump.get_parameter('Status'), {'Infusing', 'Withdrawing'}));
    results(end+1,:) = check('And leaves the cycle idle', ...
        strcmp(behaviorGUI.RigState, 'idle'));
catch ME
    results(end+1,:) = check(['Trial cycle: ' ME.message], false);
end

%% 4. A caller running its own loop is not double-driven
% run_pump_session pulses the pump itself; a GUI that also drove the cycle
% would dispense twice per trial.
try
    quiet = PumpBehaviorGUI(RUNTIME, WaitForBegin = false, DriveTrials = false);
    RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Record));
    pause(0.3)
    results(end+1,:) = check('DriveTrials=false leaves the cycle idle', ...
        strcmp(quiet.RigState, 'idle'));
catch ME
    results(end+1,:) = check(['DriveTrials: ' ME.message], false);
end

%% 5. Teardown leaves no rig timer running
try
    delete(findall(0, 'Type', 'figure', 'Tag', 'PumpBehaviorGUI'))
    drawnow
    results(end+1,:) = check('No rig timers left behind', ...
        isempty(timerfindall('Name', '*PumpBehaviorGUI*rig')));
catch ME
    results(end+1,:) = check(['Teardown: ' ME.message], false);
end

%% Cleanup
delete(findall(0, 'Type', 'figure', 'Tag', 'PumpBehaviorGUI'))
if ~isempty(pump) && isvalid(pump), delete(pump); end

reportAndExit(results);


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end


function reportAndExit(results)
labels = results(:,1);
passed = cell2mat(results(:,2));
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', ...
    sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_pump_trial_cycle:Failed', '%d smoke test(s) failed.', sum(~passed));
end
end
