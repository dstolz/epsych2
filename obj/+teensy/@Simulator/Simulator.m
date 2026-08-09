classdef Simulator < handle
    % obj = teensy.Simulator(program, Name=Value)
    % Execute a teensy.Program in MATLAB, with no board attached.
    %
    % This is the reference implementation of the firmware's execution
    % semantics. The designer's test bench runs it so a paradigm can be
    % checked before an animal ever sees it, the headless smoke tests run it,
    % and the firmware author reads it to know what to build. Where this file
    % and the firmware disagree, this file is right.
    %
    % Semantics, all of which the firmware must reproduce:
    %   1. Fixed time step (default 0.1 ms, i.e. the 10 kHz firmware ISR rate).
    %   2. Per step, in order: advance the clock; sample and debounce inputs;
    %      update edge, level and threshold detectors and counters; advance
    %      global timers and pulse generators; evaluate the current state's
    %      transitions in array order.
    %   3. The first matching transition wins. When a state timer expires on
    %      the same step as an input edge, whichever transition is listed
    %      first is taken -- which is why transition order is editable.
    %   4. On a transition: exit actions, then transition actions, then the
    %      target's entry actions.
    %   5. Entering a state resets its state timer. A self-transition resets
    %      it; a Target of "" stays without resetting.
    %   6. Digital debounce accepts a change only once the raw level has been
    %      stable for the channel's DebounceMs. Analog detection is hysteretic:
    %      high at ThresholdHigh, low at ThresholdLow, with an optional hold.
    %   7. Entering a terminal state latches RespCode and RespLatency and stops.
    %
    % Inputs are set in LOGICAL units: 0/1 for a digital channel (already
    % polarity-corrected, so 1 always means "the animal is doing the thing"),
    % and engineering units for an analog channel.
    %
    % Probability branches draw from a RandStream seeded by the Seed property,
    % so a simulated session replays identically. rand() is never called.
    %
    % Properties
    %   Program, TimeStepMs, Seed, MaxDurationMs, RecordTrace, MaxTraceSamples
    %   CurrentStateIndex, CurrentState, StateElapsedMs, TrialElapsedMs
    %   RespCode, RespLatency, Completed, Inputs, Outputs, Counters, Timers
    %
    % Methods
    %   reset, start, step, runFor, runTrial, setInput, trace
    %   monteCarlo (static), Responder (static)
    %
    % Example
    %   sim = teensy.Simulator(program);
    %   sim.start();
    %   sim.runFor(500);
    %   sim.setInput("Poke", 1);
    %   sim.runFor(2000);
    %   disp(epsych.BitMask.decode(sim.RespCode))
    %
    % See also: teensy.Program, teensy.TrialDesigner,
    %           documentation/hw/hw_Teensy_Program_Protocol.md

    properties
        TimeStepMs (1,1) double {mustBePositive} = 0.1
        Seed (1,1) double {mustBeNonnegative, mustBeInteger} = 0
        MaxDurationMs (1,1) double {mustBePositive} = 60000
        RecordTrace (1,1) logical = true
        MaxTraceSamples (1,1) double {mustBePositive} = 200000
    end

    properties (SetAccess = protected)
        Program (1,1) teensy.Program

        CurrentStateIndex (1,1) double = 0
        StateElapsedMs (1,1) double = 0
        TrialElapsedMs (1,1) double = 0

        RespCode (1,1) uint32 = uint32(0)
        RespLatency (1,1) double = NaN
        Completed (1,1) logical = false
        Running (1,1) logical = false

        Inputs (1,1) struct = struct()    % logical/engineering units, by channel name
        Outputs (1,1) struct = struct()   % 0/1 or level, by channel name
        Counters (1,1) struct = struct()
        Timers (1,1) struct = struct()    % per timer: Running, RemainingMs, Expired
        Events (1,:) struct = struct('TimeMs', {}, 'Name', {}, 'Value', {}, 'Kind', {})
    end

    properties (Dependent)
        CurrentState (1,1) string
    end

    properties (Access = private)
        rng_                              % RandStream; keeps runs reproducible
        debounce_ (1,1) struct = struct() % per digital input: Raw, Level, StableMs
        analog_ (1,1) struct = struct()   % per analog input: Above, HoldMs
        edges_ (1,1) struct = struct()    % per input: Rose, Fell for this step
        pending_ (1,:) struct = struct('AtMs', {}, 'Channel', {}, 'Value', {})
        traceT_ (1,:) double = []
        traceState_ (1,:) double = []
        traceIn_ (1,1) struct = struct()
        traceOut_ (1,1) struct = struct()
        traceCount_ (1,1) double = 0
        traceStride_ (1,1) double = 1
        stepIndex_ (1,1) double = 0
    end

    methods

        function obj = Simulator(program, options)
            % obj = teensy.Simulator(program, Name=Value)
            % Build a simulator for a program.
            %
            % Parameters
            %   program - teensy.Program to execute.
            % Name=Value
            %   TimeStepMs (double)      - Tick size in ms. Default 0.1
            %   Seed (double)            - RandStream seed. Default 0
            %   MaxDurationMs (double)   - Safety stop. Default 60000
            %   RecordTrace (logical)    - Keep a trace. Default true
            %   MaxTraceSamples (double) - Trace cap. Default 200000
            arguments
                program (1,1) teensy.Program
                options.TimeStepMs (1,1) double {mustBePositive} = 0.1
                options.Seed (1,1) double {mustBeNonnegative, mustBeInteger} = 0
                options.MaxDurationMs (1,1) double {mustBePositive} = 60000
                options.RecordTrace (1,1) logical = true
                options.MaxTraceSamples (1,1) double {mustBePositive} = 200000
            end

            obj.Program = program;
            obj.TimeStepMs = options.TimeStepMs;
            obj.Seed = options.Seed;
            obj.MaxDurationMs = options.MaxDurationMs;
            obj.RecordTrace = options.RecordTrace;
            obj.MaxTraceSamples = options.MaxTraceSamples;

            obj.reset();
        end

        function s = get.CurrentState(obj)
            % s = get.CurrentState(obj)
            % Name of the state the machine is in, or "" before start.
            if obj.CurrentStateIndex < 1 || obj.CurrentStateIndex > numel(obj.Program.States)
                s = "";
            else
                s = obj.Program.States(obj.CurrentStateIndex).Name;
            end
        end

        function reset(obj)
            % reset(obj)
            % Return every simulated resource to its idle state.
            P = obj.Program;

            obj.rng_ = RandStream('twister', Seed = obj.Seed);

            obj.CurrentStateIndex = 0;
            obj.StateElapsedMs = 0;
            obj.TrialElapsedMs = 0;
            obj.RespCode = uint32(0);
            obj.RespLatency = NaN;
            obj.Completed = false;
            obj.Running = false;
            obj.stepIndex_ = 0;

            obj.Inputs = struct();
            obj.Outputs = struct();
            obj.debounce_ = struct();
            obj.analog_ = struct();
            obj.edges_ = struct();
            obj.pending_ = struct('AtMs', {}, 'Channel', {}, 'Value', {});
            obj.Events = struct('TimeMs', {}, 'Name', {}, 'Value', {}, 'Kind', {});

            for i = 1:numel(P.Channels)
                c = P.Channels(i);
                f = obj.fieldOf_(c.Name);

                if c.Direction == "Input"
                    obj.Inputs.(f) = 0;
                    obj.edges_.(f) = [false false];
                    if c.Kind == "Digital"
                        obj.debounce_.(f) = struct('Raw', 0, 'Level', 0, 'StableMs', 0, 'AtLevelMs', 0);
                    else
                        obj.analog_.(f) = struct('Above', false, 'HeldMs', 0);
                    end
                else
                    % Outputs rest at their configured idle level, which is how
                    % a house light that is on between trials behaves.
                    obj.Outputs.(f) = c.IdleState;
                end
            end

            obj.Counters = struct();
            for i = 1:numel(P.Counters)
                obj.Counters.(obj.fieldOf_(P.Counters(i).Name)) = 0;
            end

            obj.Timers = struct();
            for i = 1:numel(P.GlobalTimers)
                obj.Timers.(obj.fieldOf_(P.GlobalTimers(i).Name)) = ...
                    struct('Running', false, 'RemainingMs', 0, 'Expired', false);
            end

            obj.traceT_ = [];
            obj.traceState_ = [];
            obj.traceIn_ = struct();
            obj.traceOut_ = struct();
            obj.traceCount_ = 0;
            obj.traceStride_ = 1;
        end

        function start(obj)
            % start(obj)
            % Begin a trial in the program's start state.
            obj.reset();

            idx = obj.Program.stateIndex(obj.Program.StartState);
            if idx == 0
                vprintf(0, 1, 'teensy.Simulator: "%s" has no valid start state', obj.Program.Name);
                return
            end

            obj.Running = true;
            obj.enterState_(idx);
        end

        function setInput(obj, channelName, value)
            % setInput(obj, channelName, value)
            % Drive an input channel.
            %
            % Parameters
            %   channelName - Input channel name.
            %   value - 0/1 for a digital channel (polarity already applied),
            %       or engineering units for an analog channel.
            arguments
                obj
                channelName (1,1) string
                value (1,1) double
            end

            f = obj.fieldOf_(channelName);
            if ~isfield(obj.Inputs, f)
                vprintf(0, 1, 'teensy.Simulator: there is no input channel named "%s"', channelName);
                return
            end
            obj.Inputs.(f) = value;
        end

        function value = getOutput(obj, channelName)
            % value = getOutput(obj, channelName)
            % Current level of an output channel, or NaN when unknown.
            f = obj.fieldOf_(channelName);
            if isfield(obj.Outputs, f)
                value = obj.Outputs.(f);
            else
                value = NaN;
            end
        end

        function step(obj, nSteps)
            % step(obj, nSteps)
            % Advance the machine by whole ticks.
            arguments
                obj
                nSteps (1,1) double {mustBePositive, mustBeInteger} = 1
            end

            for k = 1:nSteps
                if ~obj.Running || obj.Completed
                    return
                end
                obj.tick_();
            end
        end

        function runFor(obj, durationMs)
            % runFor(obj, durationMs)
            % Run until the time elapses, the trial completes, or MaxDurationMs.
            arguments
                obj
                durationMs (1,1) double {mustBePositive}
            end

            nSteps = ceil(durationMs / obj.TimeStepMs);
            for k = 1:nSteps
                if ~obj.Running || obj.Completed
                    return
                end
                if obj.TrialElapsedMs >= obj.MaxDurationMs
                    vprintf(2, 'teensy.Simulator: stopped at the %g ms safety limit', obj.MaxDurationMs);
                    obj.Running = false;
                    return
                end
                obj.tick_();
            end
        end

        function T = trace(obj)
            % T = trace(obj)
            % The recorded trace of the run so far.
            %
            % Returns:
            %   T - Struct with fields t (ms), StateIndex, StateName, Inputs,
            %       Outputs, Events, RespCode, RespLatency, Completed, Program,
            %       Seed. Inputs and Outputs are structs of vectors keyed by
            %       channel name.
            n = obj.traceCount_;

            names = strings(1, n);
            for i = 1:n
                idx = obj.traceState_(i);
                if idx >= 1 && idx <= numel(obj.Program.States)
                    names(i) = obj.Program.States(idx).Name;
                end
            end

            T = struct( ...
                't', obj.traceT_(1:n), ...
                'StateIndex', obj.traceState_(1:n), ...
                'StateName', names, ...
                'Inputs', obj.truncateTrace_(obj.traceIn_, n), ...
                'Outputs', obj.truncateTrace_(obj.traceOut_, n), ...
                'Events', obj.Events, ...
                'RespCode', obj.RespCode, ...
                'RespLatency', obj.RespLatency, ...
                'Completed', obj.Completed, ...
                'Program', obj.Program.Name, ...
                'Seed', obj.Seed);
        end
    end

    methods
        % Implemented in separate files
        T = runTrial(obj, inputScript)     % Run one trial against a scripted input
    end

    methods (Static)
        [results, summary] = monteCarlo(program, responder, nTrials, options)
        fcn = Responder(kind, options)
    end

    methods (Access = private)

        function tick_(obj)
            % tick_(obj)
            % One simulation step, in the order the firmware uses.
            dt = obj.TimeStepMs;

            obj.TrialElapsedMs = obj.TrialElapsedMs + dt;
            obj.StateElapsedMs = obj.StateElapsedMs + dt;
            obj.stepIndex_ = obj.stepIndex_ + 1;

            obj.updateInputs_(dt);
            obj.updateTimers_(dt);
            obj.applyPending_();
            obj.recordTrace_();
            obj.evaluateTransitions_();
        end

        function updateInputs_(obj, dt)
            % updateInputs_(obj, dt)
            % Debounce digital inputs, apply analog hysteresis, count edges.
            P = obj.Program;

            for i = 1:numel(P.Channels)
                c = P.Channels(i);
                if c.Direction ~= "Input"
                    continue
                end
                f = obj.fieldOf_(c.Name);
                rose = false;
                fell = false;

                if c.Kind == "Digital"
                    d = obj.debounce_.(f);
                    raw = double(obj.Inputs.(f) >= 0.5);

                    if raw == d.Raw
                        d.StableMs = d.StableMs + dt;
                    else
                        d.Raw = raw;
                        d.StableMs = 0;
                    end

                    % A change is accepted only once the raw level has held for
                    % the debounce time; a zero debounce accepts immediately.
                    if raw ~= d.Level && d.StableMs >= c.DebounceMs
                        d.Level = raw;
                        d.AtLevelMs = 0;
                        rose = raw == 1;
                        fell = raw == 0;
                    else
                        d.AtLevelMs = d.AtLevelMs + dt;
                    end

                    obj.debounce_.(f) = d;
                else
                    a = obj.analog_.(f);
                    value = obj.Inputs.(f);
                    wasAbove = a.Above;

                    % Hysteresis: rise at the high threshold, fall at the low
                    % one, so a noisy sensor sitting on the threshold does not
                    % emit a burst of spurious edges.
                    if ~a.Above && value >= c.ThresholdHigh
                        a.Above = true;
                    elseif a.Above && value <= c.ThresholdLow
                        a.Above = false;
                    end

                    if a.Above ~= wasAbove
                        a.HeldMs = 0;
                        rose = a.Above;
                        fell = ~a.Above;
                    else
                        a.HeldMs = a.HeldMs + dt;
                    end

                    obj.analog_.(f) = a;
                end

                obj.edges_.(f) = [rose fell];

                if rose || fell
                    obj.countEdges_(c.Name, rose, fell);
                end
            end
        end

        function countEdges_(obj, channelName, rose, fell)
            % countEdges_(obj, channelName, rose, fell)
            % Advance any counter watching this channel.
            P = obj.Program;
            for i = 1:numel(P.Counters)
                C = P.Counters(i);
                if ~strcmp(C.Channel, channelName)
                    continue
                end
                hit = (C.Edge == "Rising" && rose) || (C.Edge == "Falling" && fell) || ...
                    (C.Edge == "Either" && (rose || fell));
                if hit
                    f = obj.fieldOf_(C.Name);
                    obj.Counters.(f) = obj.Counters.(f) + 1;
                end
            end
        end

        function updateTimers_(obj, dt)
            % updateTimers_(obj, dt)
            % Advance running global timers and latch expiry.
            names = fieldnames(obj.Timers);
            for i = 1:numel(names)
                t = obj.Timers.(names{i});
                if ~t.Running
                    continue
                end
                t.RemainingMs = t.RemainingMs - dt;
                if t.RemainingMs <= 0
                    t.Running = false;
                    t.RemainingMs = 0;
                    t.Expired = true;
                end
                obj.Timers.(names{i}) = t;
            end
        end

        function applyPending_(obj)
            % applyPending_(obj)
            % Apply scheduled output changes whose time has arrived.
            if isempty(obj.pending_)
                return
            end

            due = [obj.pending_.AtMs] <= obj.TrialElapsedMs;
            for k = find(due)
                obj.Outputs.(obj.fieldOf_(obj.pending_(k).Channel)) = obj.pending_(k).Value;
            end
            obj.pending_(due) = [];
        end

        function evaluateTransitions_(obj)
            % evaluateTransitions_(obj)
            % Take the first transition whose condition is satisfied.
            if obj.CurrentStateIndex < 1
                return
            end

            S = obj.Program.States(obj.CurrentStateIndex);

            for k = 1:numel(S.Transitions)
                T = S.Transitions(k);
                if ~obj.evaluate_(T.Condition)
                    continue
                end

                if strlength(T.Target) == 0
                    % Stay put: run the actions but do not reset the timer.
                    obj.runActions_(T.Actions);
                    return
                end

                targetIdx = obj.Program.stateIndex(T.Target);
                if targetIdx == 0
                    vprintf(0, 1, 'teensy.Simulator: transition targets missing state "%s"', T.Target);
                    return
                end

                obj.runActions_(S.ExitActions);
                obj.runActions_(T.Actions);
                obj.enterState_(targetIdx);
                return
            end
        end

        function enterState_(obj, idx)
            % enterState_(obj, idx)
            % Enter a state: reset its timer, apply its bits, run entry actions.
            obj.CurrentStateIndex = idx;
            obj.StateElapsedMs = 0;

            S = obj.Program.States(idx);
            obj.logEvent_("state", S.Name, idx);

            mask = S.respMask();
            if mask ~= 0
                obj.RespCode = bitor(obj.RespCode, uint32(mask));
            end

            obj.runActions_(S.EntryActions);

            if S.IsTerminal
                obj.Completed = true;
                obj.Running = false;
                obj.logEvent_("complete", S.Name, double(obj.RespCode));

                % Force a final sample so the outcome state and the outputs its
                % entry actions drove appear on the timeline. Without this the
                % trace stops at the state before the outcome, which reads as
                % though the trial never finished.
                obj.recordTrace_(true);
            end
        end

        function runActions_(obj, actions)
            % runActions_(obj, actions)
            % Execute an action array in order.
            for i = 1:numel(actions)
                obj.runAction_(actions(i));
            end
        end

        function runAction_(obj, A)
            % runAction_(obj, A)
            % Execute one action.
            P = obj.Program;

            switch A.Kind
                case "SetOutput"
                    obj.setOutputNow_(A.Channel, P.resolve(A.Value));

                case "Pulse"
                    obj.schedulePulse_(A.Channel, P.resolve(A.DelayMs), P.resolve(A.WidthMs));

                case "PulseTrain"
                    width = P.resolve(A.WidthMs);
                    period = P.resolve(A.PeriodMs);
                    count = max(1, round(P.resolve(A.Count)));
                    for n = 0:count-1
                        obj.schedulePulse_(A.Channel, n * period, width);
                    end

                case "AnalogOut"
                    obj.setOutputNow_(A.Channel, P.resolve(A.Value));

                case "StartTimer"
                    f = obj.fieldOf_(A.Timer);
                    if isfield(obj.Timers, f)
                        duration = P.resolve(A.Value);
                        if ~(duration > 0)
                            duration = P.resolve(obj.timerDuration_(A.Timer));
                        end
                        obj.Timers.(f) = struct('Running', true, ...
                            'RemainingMs', duration, 'Expired', false);
                    end

                case "CancelTimer"
                    f = obj.fieldOf_(A.Timer);
                    if isfield(obj.Timers, f)
                        obj.Timers.(f) = struct('Running', false, 'RemainingMs', 0, 'Expired', false);
                    end

                case "ResetCounter"
                    f = obj.fieldOf_(A.Counter);
                    if isfield(obj.Counters, f)
                        obj.Counters.(f) = 0;
                    end

                case "IncrementCounter"
                    f = obj.fieldOf_(A.Counter);
                    if isfield(obj.Counters, f)
                        obj.Counters.(f) = obj.Counters.(f) + max(1, round(P.resolve(A.Value)));
                    end

                case "AddRespCode"
                    obj.RespCode = bitor(obj.RespCode, uint32(A.respMask()));
                    obj.logEvent_("respcode", "RespCode", double(obj.RespCode));

                case "MarkLatency"
                    obj.RespLatency = obj.TrialElapsedMs;
                    obj.logEvent_("latency", "RespLatency", obj.RespLatency);

                case "LogEvent"
                    obj.logEvent_("user", A.EventName, P.resolve(A.Value));

                case "SetVariable"
                    idx = P.variableIndex(A.Variable);
                    if idx > 0
                        P.Variables(idx).Value = P.resolve(A.Value);
                    end

                case "Sync"
                    obj.schedulePulse_(A.Channel, 0, P.resolve(A.WidthMs));

                case "EndTrial"
                    obj.Completed = true;
                    obj.Running = false;
                    obj.logEvent_("complete", "EndTrial", double(obj.RespCode));
            end
        end

        function d = timerDuration_(obj, name)
            % d = timerDuration_(obj, name)
            % Configured duration of a global timer, or 0 when unknown.
            d = 0;
            idx = obj.Program.timerIndex(name);
            if idx > 0
                d = obj.Program.GlobalTimers(idx).DurationMs;
            end
        end

        function setOutputNow_(obj, channelName, value)
            % setOutputNow_(obj, channelName, value)
            % Drive an output immediately.
            f = obj.fieldOf_(channelName);
            if ~isfield(obj.Outputs, f)
                return
            end
            obj.Outputs.(f) = value;
            obj.logEvent_("output", channelName, value);
        end

        function schedulePulse_(obj, channelName, delayMs, widthMs)
            % schedulePulse_(obj, channelName, delayMs, widthMs)
            % Queue a rising then falling edge on an output.
            f = obj.fieldOf_(channelName);
            if ~isfield(obj.Outputs, f)
                return
            end

            if ~(widthMs > 0)
                widthMs = 1;
            end
            if ~(delayMs > 0)
                delayMs = 0;
            end

            onAt = obj.TrialElapsedMs + delayMs;

            % An undelayed pulse goes high now rather than waiting for the next
            % applyPending_. Without this, a reward pulse fired on entry to a
            % terminal state would never appear at all: entering a terminal
            % state stops the run, so there is no next step to apply it on. The
            % firmware behaves the same way -- its pulse generator is hardware
            % timed and keeps running after TrialComplete is raised.
            if delayMs == 0
                obj.Outputs.(f) = 1;
            else
                obj.pending_(end+1) = struct('AtMs', onAt, 'Channel', channelName, 'Value', 1);
            end

            obj.pending_(end+1) = struct('AtMs', onAt + widthMs, 'Channel', channelName, 'Value', 0);
            obj.logEvent_("pulse", channelName, widthMs);
        end

        function tf = evaluate_(obj, C)
            % tf = evaluate_(obj, C)
            % Evaluate a condition tree against the current simulated state.
            P = obj.Program;

            switch C.Kind
                case "Always"
                    tf = true;

                case "Never"
                    tf = false;

                case "And"
                    tf = true;
                    for i = 1:numel(C.Operands)
                        if ~obj.evaluate_(C.Operands(i))
                            tf = false;
                            return
                        end
                    end

                case "Or"
                    tf = false;
                    for i = 1:numel(C.Operands)
                        if obj.evaluate_(C.Operands(i))
                            tf = true;
                            return
                        end
                    end

                case "Not"
                    tf = ~isempty(C.Operands) && ~obj.evaluate_(C.Operands(1));

                case "StateTimer"
                    after = P.resolve(C.HoldMs);
                    if ~(after > 0)
                        after = P.resolve(obj.Program.States(obj.CurrentStateIndex).DurationMs);
                    end
                    tf = isfinite(after) && obj.StateElapsedMs >= after;

                case "GlobalTimer"
                    f = obj.fieldOf_(C.Timer);
                    tf = isfield(obj.Timers, f) && obj.Timers.(f).Expired;

                case "DigitalEdge"
                    f = obj.fieldOf_(C.Channel);
                    if ~isfield(obj.edges_, f)
                        tf = false;
                        return
                    end
                    e = obj.edges_.(f);
                    switch C.Edge
                        case "Rising",  tf = e(1);
                        case "Falling", tf = e(2);
                        otherwise,      tf = e(1) || e(2);
                    end

                case "DigitalLevel"
                    f = obj.fieldOf_(C.Channel);
                    if ~isfield(obj.debounce_, f)
                        tf = false;
                        return
                    end
                    d = obj.debounce_.(f);
                    hold = P.resolve(C.HoldMs);
                    tf = d.Level == C.Level && d.AtLevelMs >= max(0, hold);

                case "AnalogThreshold"
                    tf = obj.evaluateAnalog_(C);

                case "Counter"
                    f = obj.fieldOf_(C.Counter);
                    if ~isfield(obj.Counters, f)
                        tf = false;
                        return
                    end
                    tf = localCompare_(obj.Counters.(f), C.CompareOp, P.resolve(C.Count));

                case "Probability"
                    % Drawn once per evaluation from the seeded stream, so a
                    % run replays exactly for a given Seed.
                    tf = rand(obj.rng_) < P.resolve(C.Probability);

                otherwise
                    tf = false;
            end
        end

        function tf = evaluateAnalog_(obj, C)
            % tf = evaluateAnalog_(obj, C)
            % Evaluate an analog threshold condition.
            f = obj.fieldOf_(C.Channel);
            if ~isfield(obj.analog_, f)
                tf = false;
                return
            end

            a = obj.analog_.(f);
            e = obj.edges_.(f);
            hold = max(0, obj.Program.resolve(C.HoldMs));

            switch C.Compare
                case "Above",     tf = a.Above && a.HeldMs >= hold;
                case "Below",     tf = ~a.Above && a.HeldMs >= hold;
                case "CrossUp",   tf = e(1);
                case "CrossDown", tf = e(2);
                otherwise,        tf = false;
            end
        end

        function logEvent_(obj, kind, name, value)
            % logEvent_(obj, kind, name, value)
            % Append to the timestamped event log.
            obj.Events(end+1) = struct('TimeMs', obj.TrialElapsedMs, ...
                'Name', string(name), 'Value', double(value), 'Kind', string(kind));
        end

        function recordTrace_(obj, force)
            % recordTrace_(obj, force)
            % Append one trace sample, thinning once the cap is reached.
            %
            % force bypasses the stride so a significant moment -- entering a
            % terminal state -- is always captured.
            arguments
                obj
                force (1,1) logical = false
            end

            if ~obj.RecordTrace
                return
            end

            if ~force && mod(obj.stepIndex_ - 1, obj.traceStride_) ~= 0
                return
            end

            % At the cap, throw away every other sample and double the stride,
            % so an arbitrarily long run stays inside a fixed memory budget
            % while keeping uniform coverage of the whole run.
            if obj.traceCount_ >= obj.MaxTraceSamples
                keep = 1:2:obj.traceCount_;
                obj.traceT_ = obj.traceT_(keep);
                obj.traceState_ = obj.traceState_(keep);
                obj.traceIn_ = obj.thinTrace_(obj.traceIn_, keep);
                obj.traceOut_ = obj.thinTrace_(obj.traceOut_, keep);
                obj.traceCount_ = numel(keep);
                obj.traceStride_ = obj.traceStride_ * 2;
            end

            n = obj.traceCount_ + 1;
            obj.traceT_(n) = obj.TrialElapsedMs;
            obj.traceState_(n) = obj.CurrentStateIndex;

            inNames = fieldnames(obj.Inputs);
            for i = 1:numel(inNames)
                f = inNames{i};
                if isfield(obj.debounce_, f)
                    obj.traceIn_.(f)(n) = obj.debounce_.(f).Level;
                else
                    obj.traceIn_.(f)(n) = obj.Inputs.(f);
                end
            end

            outNames = fieldnames(obj.Outputs);
            for i = 1:numel(outNames)
                obj.traceOut_.(outNames{i})(n) = obj.Outputs.(outNames{i});
            end

            obj.traceCount_ = n;
        end

        function S = thinTrace_(~, S, keep)
            % S = thinTrace_(obj, S, keep)
            % Keep a subset of samples in every channel of a trace struct.
            names = fieldnames(S);
            for i = 1:numel(names)
                S.(names{i}) = S.(names{i})(keep);
            end
        end

        function S = truncateTrace_(~, S, n)
            % S = truncateTrace_(obj, S, n)
            % Clip every channel of a trace struct to n samples.
            names = fieldnames(S);
            for i = 1:numel(names)
                v = S.(names{i});
                S.(names{i}) = v(1:min(n, numel(v)));
            end
        end

        function f = fieldOf_(~, name)
            % f = fieldOf_(obj, name)
            % Struct field name for a channel, counter or timer name.
            f = matlab.lang.makeValidName(char(name));
        end
    end
end


function tf = localCompare_(value, op, threshold)
% tf = localCompare_(value, op, threshold)
% Apply a counter comparison operator.
switch op
    case "GT", tf = value > threshold;
    case "LE", tf = value <= threshold;
    case "LT", tf = value < threshold;
    case "EQ", tf = value == threshold;
    otherwise, tf = value >= threshold;
end
end
