% smoke_test_syringepump_example.m
% Headless check of the examples/syringepump worked example — no pump required.
%
% Builds the protocol against tmp/NE1000_Mock, runs a short session through
% run_pump_session, and asserts what the example claims: the pump's Volume
% becomes a per-trial trial-table column, PumpBehaviorGUI opens with a
% gui.components.SyringePump panel bound to the session's pump, and the volume the pump
% reports back lands in DATA.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_syringepump_example.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.components.SyringePump', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'examples', 'syringepump'));

fprintf('\n=== SyringePump Example Smoke Test ===\n\n');
results = {};

RUNTIME = [];
behaviorGUI = [];

%% 1. The protocol compiles with the pump as a trial-table column
try
    [P, pump] = create_pump_protocol('', Save = false);

    results(end+1,:) = check('Protocol carries an hw.NE1000', ...
        any(arrayfun(@(i) isa(i, 'hw.NE1000'), P.Interfaces)));
    results(end+1,:) = check('Pump connected for the build', pump.IsConnected);
    results(end+1,:) = check('Rate units authored as uL/min', strcmp(pump.RateUnits, 'UM'));
    results(end+1,:) = check('One condition per reward volume', P.COMPILED.ntrials == 3);
    results(end+1,:) = check('Volume is a trial-table column', ...
        ismember('Volume', P.COMPILED.writeparams));
    results(end+1,:) = check('Rate is a trial-table column', ...
        ismember('Rate', P.COMPILED.writeparams));

    col = find(strcmp(P.COMPILED.writeparams, 'Volume'), 1);
    levels = sort(cell2mat(P.COMPILED.trials(:, col)))';
    results(end+1,:) = check('Reward volumes are 20/40/60 uL', ...
        isequal(round(levels * 1000), [20 40 60]));
    results(end+1,:) = check('Volume labeled from the syringe, not the rate units', ...
        strcmp(pump.find_parameter('Volume').Unit, 'mL'));
    delete(pump)
catch ME
    results(end+1,:) = check(['Protocol: ' ME.message], false);
end

%% 1b. The saved .eprot reloads with an offline pump carrying its parameters
eprot = [tempname '.eprot'];
try
    [~, pump] = create_pump_protocol(eprot);
    delete(pump)

    Q = epsych.Protocol.load(eprot);
    reloaded = Q.Interfaces(arrayfun(@(i) isa(i, 'hw.NE1000'), Q.Interfaces));
    results(end+1,:) = check('Reloads as an hw.NE1000', isscalar(reloaded));
    results(end+1,:) = check('Reloads offline', ~reloaded.IsConnected);

    pv = reloaded.find_parameter('Volume');
    results(end+1,:) = check('Reward levels survived the round trip', ...
        isequal(round(cell2mat(pv.Values) * 1000), [20 40 60]));
    results(end+1,:) = check('Corrected unit label survived', strcmp(pv.Unit, 'mL'));

    Q.compile();
    results(end+1,:) = check('The reloaded protocol still compiles', Q.COMPILED.ntrials == 3);
    delete(reloaded)
catch ME
    results(end+1,:) = check(['Round trip: ' ME.message], false);
end
if isfile(eprot), delete(eprot); end

%% 2. A session runs, the GUI opens, and the pump reports back
try
    % WaitForBegin=false: with no operator to press Begin Experiment, the
    % session would hold at the button forever. The gate itself is
    % exercised in section 3b.
    RUNTIME = run_pump_session(NumTrials = 4, TrialPause = 0, WaitForBegin = false);

    D = RUNTIME.TRIALS(1).DATA;
    results(end+1,:) = check('Every trial produced a DATA record', numel(D) == 4);
    results(end+1,:) = check('DATA carries the pump read-back', ...
        isfield(D, 'VolumeInfused') && isfield(D, 'VolumeWithdrawn'));
    results(end+1,:) = check('Infused volume accumulates across trials', ...
        D(end).VolumeInfused > D(1).VolumeInfused);
    results(end+1,:) = check('Each trial dispensed its own reward size', ...
        all(abs(diff([D.VolumeInfused]) - [D(2:end).Volume]) < 1e-9));
    results(end+1,:) = check('Dispatched volumes come from the level list', ...
        all(ismember(round([D.Volume] * 1000), [20 40 60])));
catch ME
    results(end+1,:) = check(['Session: ' ME.message], false);
end

%% 3. The behavior GUI is bound to the session's pump
try
    fig = findall(0, 'Type', 'figure', 'Tag', 'PumpBehaviorGUI');
    results(end+1,:) = check('PumpBehaviorGUI opened', ~isempty(fig));

    behaviorGUI = fig(1).UserData;   % gui.BehaviorGUI parks itself there
    results(end+1,:) = check('Figure carries the PumpBehaviorGUI', isa(behaviorGUI, 'PumpBehaviorGUI'));
    results(end+1,:) = check('It built a gui.components.SyringePump panel', ...
        isa(behaviorGUI.Pump, 'gui.components.SyringePump'));

    sessionPump = RUNTIME.Interfaces(arrayfun(@(i) isa(i, 'hw.NE1000'), RUNTIME.Interfaces));
    results(end+1,:) = check('The panel adopted the session pump', ...
        behaviorGUI.Pump.Interface == sessionPump);
    results(end+1,:) = check('The panel reports the link is up', behaviorGUI.Pump.IsConnected);
    results(end+1,:) = check('The panel read a volume back', ...
        ~isnan(behaviorGUI.Pump.VolumeInfused));
    results(end+1,:) = check('Session pump is still connected', sessionPump.IsConnected);
    results(end+1,:) = check('Session pump was left stopped', ...
        ~ismember(sessionPump.get_parameter('Status'), {'Infusing', 'Withdrawing'}));

    % The run started without the button, so the GUI has to have picked it
    % up from the mode changes rather than leaving the gate closed.
    btn = findall(fig(1), 'Type', 'uibutton', '-and', 'Enable', 'off');
    results(end+1,:) = check('A session elsewhere opens the gate', behaviorGUI.BeginRequested);
    results(end+1,:) = check('Its button retired to a status line', ...
        any(strcmp({btn.Text}, 'Session Complete')));
catch ME
    results(end+1,:) = check(['Behavior GUI: ' ME.message], false);
end

%% 3b. Trials wait for Begin Experiment
% A fresh instance over the same runtime: this one has seen no Record, so
% its gate is still shut — the state an operator meets when the window
% opens. (Constructing it replaces the window found above; the checks in
% section 4 hold for either instance.) WaitForBegin=false so the
% constructor returns; that it does NOT return when the gate is on is what
% section 3c measures. DriveTrials=false throughout these gate sections:
% the trial cycle is tmp/smoke_test_pump_trial_cycle.m's subject, and an
% instance driving it here would dispense into an already-finished session.
tFree = NaN;
try
    c = tic;
    gated = PumpBehaviorGUI(RUNTIME, WaitForBegin = false, DriveTrials = false);
    tFree = toc(c);
    beginBtn = findall(gated.h_figure, 'Type', 'uibutton', ...
        '-and', 'Text', 'Begin Experiment');

    results(end+1,:) = check('The GUI opens with a Begin Experiment button', isscalar(beginBtn));
    results(end+1,:) = check('It is enabled and waiting', strcmp(beginBtn.Enable, 'on'));
    results(end+1,:) = check('The gate starts shut', ~gated.BeginRequested);
    results(end+1,:) = check('waitForBegin holds while it is shut', ~gated.waitForBegin(0.3));

    beginBtn.ButtonPushedFcn(beginBtn, []);   % press it exactly as the operator does

    results(end+1,:) = check('Pressing it releases the session', gated.BeginRequested);
    results(end+1,:) = check('waitForBegin returns once released', gated.waitForBegin(1));
    results(end+1,:) = check('The button retires after the press', ...
        strcmp(beginBtn.Enable, 'off') && strcmp(beginBtn.Text, 'Experiment Running'));
catch ME
    results(end+1,:) = check(['Begin gate: ' ME.message], false);
end

%% 3c. The gate is the CONSTRUCTOR's, which is what holds a RunExpt session
% RunExpt builds the behavior GUI from the PsychTimer's StartFcn and start()
% does not return until that callback does, so a constructor that blocks
% blocks the trial loop. Nothing in run_pump_session is in that path, which
% is why the hold cannot live there. Measured against an ungated build so
% the assertion is about the wait, not about how long uifigure takes.
try
    assert(~isnan(tFree), 'the ungated build did not complete')
    hold_ = round(tFree + 0.6, 3);   % StartDelay is millisecond-precision

    % Repeating, because the button only exists once build() has run: a
    % single-shot press timed to land mid-wait would be a race.
    presser = timer('Name', 'PumpGateProbe', 'StartDelay', hold_, ...
        'Period', 0.1, 'ExecutionMode', 'fixedSpacing', 'TasksToExecute', 50, ...
        'TimerFcn', @(~,~) pressBegin());
    start(presser)

    c = tic;
    held = PumpBehaviorGUI(RUNTIME, DriveTrials = false);   % must not return until pressBegin fires
    tHeld = toc(c);

    results(end+1,:) = check('The constructor blocks until Begin is pressed', tHeld > hold_);
    results(end+1,:) = check('It returns once the button is pressed', ...
        isvalid(held) && held.BeginRequested);
catch ME
    results(end+1,:) = check(['Constructor gate: ' ME.message], false);
end
t = timerfindall('Name', 'PumpGateProbe');
if ~isempty(t), stop(t); delete(t); end

%% 3d. Preview retires the button, exactly as Record does
% hw.DeviceState.Preview is a distinct state that is not isIdle, and
% RunExpt.PsychTimerStart broadcasts it for every Preview run. Matching only
% Record left the button green, enabled, and inert for the whole run.
try
    previewed = PumpBehaviorGUI(RUNTIME, WaitForBegin = false, DriveTrials = false);
    previewBtn = findall(previewed.h_figure, 'Type', 'uibutton', ...
        '-and', 'Text', 'Begin Experiment');
    results(end+1,:) = check('A fresh instance starts shut', ...
        ~previewed.BeginRequested && strcmp(previewBtn.Enable, 'on'));

    RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Preview));
    drawnow

    results(end+1,:) = check('Preview opens the gate', previewed.BeginRequested);
    results(end+1,:) = check('Preview retires the button', ...
        strcmp(previewBtn.Enable, 'off') && strcmp(previewBtn.Text, 'Preview Running'));
catch ME
    results(end+1,:) = check(['Preview gate: ' ME.message], false);
end

%% 4. Teardown leaves nothing behind
try
    fig = findall(0, 'Type', 'figure', 'Tag', 'PumpBehaviorGUI');
    sessionPump = RUNTIME.Interfaces(arrayfun(@(i) isa(i, 'hw.NE1000'), RUNTIME.Interfaces));
    delete(fig)
    drawnow

    results(end+1,:) = check('Closing the GUI keeps the borrowed pump', ...
        isvalid(sessionPump) && sessionPump.IsConnected);
    results(end+1,:) = check('No pump readout timers left behind', ...
        isempty(timerfindall('Name', 'SyringePump_Timer_*')));

    delete(sessionPump)
catch ME
    results(end+1,:) = check(['Teardown: ' ME.message], false);
end

%% Cleanup
delete(findall(0, 'Type', 'figure', 'Tag', 'PumpBehaviorGUI'))

%% Summary
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
    error('smoke_test_syringepump_example:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end


function pressBegin()
% Stand in for the operator, from a timer callback — the same place a real
% click arrives from while the constructor pauses. Quiet when the button is
% not there yet (build has not run) or is already retired (text changed).
f = findall(0, 'Type', 'figure', 'Tag', 'PumpBehaviorGUI');
if isempty(f), return; end
b = findall(f(1), 'Type', 'uibutton', '-and', 'Text', 'Begin Experiment');
if isempty(b), return; end
b(1).ButtonPushedFcn(b(1), []);
end
