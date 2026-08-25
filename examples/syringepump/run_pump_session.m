function RUNTIME = run_pump_session(options)
% RUNTIME = run_pump_session(Name=Value, ...)
% Drive PumpBehaviorGUI — and with it the gui.components.SyringePump panel — through a
% session, with a real NE-1000 or the in-process simulated pump.
%
% Each trial writes the trial table's reward Volume to the pump, pulses
% Start, waits for the dispense to finish, then collects the pump's
% read-back parameters into DATA exactly as ep_TimerFcn_RunTime does. What
% you should see: the panel's readout climbing after every reward, its
% status line turning green while the motor runs, the monitor and the
% scatter following DATA, and manual Start / Stop / Zero still working
% between trials.
%
% The session holds at the GUI's Begin Experiment button until the operator
% presses it, so the syringe can be seated and the line purged first — the
% pump panel is fully live while it waits. Closing the window instead calls
% the run off before any liquid moves.
%
% Name=Value:
%   NumTrials     - Trials to run. Default 12.
%   Port          - Serial port of a real pump. Default '' (simulated pump).
%   ShowGUI       - Launch PumpBehaviorGUI. Default true.
%   WaitForBegin  - Hold for the GUI's Begin Experiment button. Default
%                   true; ignored with ShowGUI=false, where there is no
%                   button to press (headless tests run that way).
%   TrialPause    - Seconds between trials, overriding the protocol's ITI.
%                   Default [] (use the dispatched ITI, 2-4 s).
%   Diameter      - Syringe inside diameter, mm. Default 21.59.
%
% Returns:
%   RUNTIME - The epsych.Runtime, with the session's DATA in TRIALS(1).DATA.
%
% Try it:
%   run_pump_session                      % simulated pump, 12 rewards
%   run_pump_session(Port = 'COM4')       % a real NE-1000 on COM4
%
% See also create_pump_protocol, PumpBehaviorGUI, gui.components.SyringePump, hw.NE1000

arguments
    options.NumTrials (1,1) double {mustBeInteger, mustBePositive} = 12
    options.Port (1,:) char = ''
    options.ShowGUI (1,1) logical = true
    options.WaitForBegin (1,1) logical = true
    options.TrialPause double {mustBeScalarOrEmpty, mustBeNonnegative} = []
    options.Diameter (1,1) double {mustBeInRange(options.Diameter, 0.1, 50)} = 21.59
end

here = fileparts(mfilename('fullpath'));
addpath(here); % PumpBehaviorGUI must be reachable

% --- Protocol, built against a live pump ---------------------------------
% Not loaded from the .eprot: a saved protocol reloads with an OFFLINE
% interface, and epsych.Runtime asserts that every interface connects.
[P, pump] = create_pump_protocol('', Port = options.Port, ...
    Diameter = options.Diameter, Save = false);
cleanup = onCleanup(@() stopPump_(pump));

% --- Runtime scaffold: what RunExpt + ep_TimerFcn_Start normally do ------
RUNTIME = epsych.Runtime;
RUNTIME.isTest = true;
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;

subject = epsych.DefaultSubject(struct('Name', 'PumpTest', ...
    'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));

C = P.COMPILED;
T = struct;
T.protocol    = P;
T.Subject     = subject;
T.BoxID       = subject.BoxID;
T.parameters  = C.parameters;
T.trials      = C.trials;
T.writeparams = C.writeparams;
idx = struct;
for k = 1:numel(C.writeparams)
    idx.(C.writeparams{k}) = k;
end
T.writeParamIdx = idx;
T.selector = epsych.TrialSelector.create(struct('trialFunc', C.OPTIONS.trialFunc));
T.selector.initialize(T);
T.FORCE_TRIAL         = false;
T.RECOMPILE_REQUESTED = false;
T.DataFilename        = '';
T.TrialIndex          = 1;
T.NextTrialID         = T.selector.selectNext(T);

T.selector.setRuntime(RUNTIME, 1);
RUNTIME.TRIALS = T; % the setter resolves required triggers and dispatches trial 1

% RunExpt launches the behavior GUI right after ep_TimerFcn_Start, then
% broadcasts the session mode; mirror that order here, with the operator's
% go-ahead in between. Record is broadcast only once the run is committed,
% so nothing downstream sees a session that never started.
if options.ShowGUI
    % The gate is the constructor's, not this script's: it has to hold a
    % RunExpt session too, where nothing here is in the call path.
    %
    % DriveTrials=false because the loop below is the trial loop here. In a
    % RunExpt session there is no such loop — the runtime writes the reward
    % and waits on x_TrialComplete_1 — so the GUI runs the cycle itself, and
    % leaving its default on would pulse the pump twice per trial.
    behaviorGUI = PumpBehaviorGUI(RUNTIME, WaitForBegin = options.WaitForBegin, ...
        DriveTrials = false);
    if options.WaitForBegin && ~(isvalid(behaviorGUI) && behaviorGUI.BeginRequested)
        vprintf(0, 'Session cancelled: the window was closed before the experiment began.')
        if nargout == 0, clear RUNTIME; end
        return
    end
end
RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Record));

% --- Trial loop ----------------------------------------------------------
pVol  = pump.find_parameter('Volume');
pRate = pump.find_parameter('Rate');
pITI  = RUNTIME.find_parameter('ITI');

% The accumulators are never assumed to start at zero: the pump resets them
% on power-up, on a diameter change, and at 9999, so only differences mean
% anything (the same caveat the panel's readout carries).
startInfused = pump.get_parameter('VolumeInfused');

for k = 1:options.NumTrials
    % dispatchNextTrial already wrote this trial's Volume and Rate to the
    % pump, so the reward is configured; Start is all that is left.
    vol  = pVol(1).Value;
    rate = pRate(1).Value;

    vprintf(1, 'Trial %d: dispensing %.3f mL at %.4g uL/min', k, vol, rate)
    pump.trigger('Start');
    awaitDispense_(pump, vol, rate);

    % --- Trial completion, exactly as ep_TimerFcn_RunTime does it --------
    % The Read sweep is what queries the pump for its dispensed volumes.
    data = RUNTIME.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
    data.TrialIndex        = RUNTIME.TRIALS(1).TrialIndex;
    data.TrialID           = RUNTIME.TRIALS(1).NextTrialID;
    data.computerTimestamp = datetime('now');
    data.isTest            = RUNTIME.isTest;

    ti = RUNTIME.TRIALS(1).TrialIndex;
    if ti == 1
        RUNTIME.TRIALS(1).DATA = data;
    else
        RUNTIME.TRIALS(1).DATA(ti) = data;
    end

    RUNTIME.TRIALS(1).selector.onComplete(RUNTIME.TRIALS(1).NextTrialID, data);
    RUNTIME.EVENTS.notify('NewData', epsych.TrialsData(RUNTIME.TRIALS(1)));

    RUNTIME.TRIALS(1).TrialIndex = ti + 1;
    if k < options.NumTrials
        RUNTIME.TRIALS(1).NextTrialID = ...
            RUNTIME.TRIALS(1).selector.selectNext(RUNTIME.TRIALS(1));
        RUNTIME.dispatchNextTrial(1);

        iti = options.TrialPause;
        if isempty(iti), iti = pITI(1).Value; end
        pauseWithGraphics_(iti);
    end
    drawnow limitrate
end

RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Stop));

D = RUNTIME.TRIALS(1).DATA;
vprintf(0, 'Session complete: %d trials, %.3f mL infused in total', ...
    numel(D), D(end).VolumeInfused - startInfused)

if nargout == 0, clear RUNTIME; end
end


function awaitDispense_(pump, vol, rate)
% awaitDispense_(pump, vol, rate)
% Block until the pump has delivered `vol` mL at `rate` uL/min.
%
% A real pump given a non-zero Volume stops itself, so this polls Status
% and never issues a Stop that would truncate the dispense. The simulated
% pump models no motion at all, so its accumulator is advanced by hand —
% the one place this script knows it is talking to a mock.
expected = 60 * vol * 1000 / max(rate, eps);   % mL, uL/min -> seconds

if isa(pump, 'NE1000_Mock')
    % The volume is banked at the START of the wait, not the end: the pump's
    % DIS reply is cached for DispenseCacheInterval, so a reading taken the
    % instant after the accumulator moved can still be the value from before
    % it. A real pump moves liquid throughout the dispense and has settled
    % long before it reports Stopped; stepping the accumulator first models
    % that, instead of an impossible change at the final millisecond.
    pump.SimInfused = pump.SimInfused + vol;
    pauseWithGraphics_(max(min(expected, 2), 0.2));
    pump.SimStatus = 'S';
    return
end

deadline = tic;
timeout = 3 * expected + 2;
while toc(deadline) < timeout
    % strcmp, not ismember: a pump that misses a query answers 'Unknown', and
    % ismember would reject a value it could not compare against the cell.
    if ~any(strcmp(pump.get_parameter('Status'), {'Infusing', 'Withdrawing'}))
        return
    end
    pauseWithGraphics_(0.05);
end
vprintf(0, 1, 'Pump still running %.1f s after Start — check the syringe and Volume.', timeout)
end


function pauseWithGraphics_(seconds)
% Wait while keeping the GUI, and the pump panel's own readout timer, live.
if seconds <= 0
    drawnow limitrate
    return
end
t = tic;
while toc(t) < seconds
    pause(min(0.05, seconds));
    drawnow limitrate
end
end


function stopPump_(pump)
% Safety backstop: an error or Ctrl-C anywhere above must not leave the
% pusher advancing. hw.NE1000 also stops on delete, but this runs first and
% while the interface is still known to be connected.
if isvalid(pump) && pump.IsConnected
    try
        pump.trigger('Stop');
    catch ME
        vprintf(0, 1, ME);
    end
end
end
