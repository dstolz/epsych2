classdef RigPreviewSubject < handle
    % S = RigPreviewSubject(rx)
    % S = RigPreviewSubject(rx, NumTrials=250, ProfileTrials=20, ...)
    % A simulated subject for a real Preview of the appetitive platform
    % task, and the recorder of what that session cost. The working half of
    % tmp/bench_rig_preview.m.
    %
    % The subject is the circuit's own spoof tags, used the way an animal's
    % real sessions show the circuit reads one:
    %
    %   ManualTrigger = 1 ("spoof platform")   on the platform: a trial starts
    %   ... = 0 during RespWindow              THE RESPONSE: a Hit, or a False
    %                                          Alarm on a catch trial; the
    %                                          trial ends at once
    %   ... = 0 during DelayPeriod             an Abort
    %   staying through the window             a Miss, which ends by itself --
    %                                          or on a catch trial a Correct
    %                                          Reject, which completes only at
    %                                          the trough (SpoofTrough)
    %
    % The response is LEAVING THE PLATFORM, not entering the trough: holding
    % the platform spoof high and pulsing SpoofTrough in the window scores a
    % Miss. Whether the subject responds is a psychometric function of the
    % depth on the device, so the staircase tracks and reverses as it does for
    % an animal, and every display has real outcomes to draw.
    %
    % HITS AND CORRECT REJECTS FIRE THE REAL PELLET DISPENSER: about two
    % trials in three.
    %
    % Everything that touches the runtime happens inside this object's own
    % timer callback. A timer callback is never interrupted by another, while
    % top-level code that reads RUNTIME.TRIALS under a running session timer
    % corrupts the heap (tmp/OddballSessionDriver.m documents it).
    %
    % Needs these parameters, by name: TrialDelivery, ManualTrigger,
    % SpoofTrough, InTrial, DelayPeriod, RespWindow, Depth, and a TrialType
    % column in the trial table (0 stimulus, 1 catch, 2 reminder).
    %
    % Properties:
    %   Finished - true once the session has been stopped and collected
    %   Outcome  - 'complete', or why it ended early
    %   Results  - struct, filled when Finished; see bench_rig_report
    %
    % Methods:
    %   start    - step onto the platform and begin
    %
    % See also: bench_rig_preview, bench_rig_tick, bench_rig_report,
    %           cl_AppetitiveStimDetect, epsych.TickStats

    properties (SetAccess = private)
        RX                                       % epsych.RunExpt running the Preview
        NumTrials (1,1) double = 250             % trials that are timed
        ProfileTrials (1,1) double = 0           % further trials run under the profiler
        Threshold (1,1) double = -12             % depth (dB) at the middle of the psychometric function
        Slope (1,1) double = 3                   % its standard deviation (dB)
        FalseAlarmRate (1,1) double = 0.10
        LapseRate (1,1) double = 0.03
        AbortRate (1,1) double = 0.07            % share of trials left during the delay
        Seed (1,1) double = 1
        MaxSeconds (1,1) double = 3600
        Finished (1,1) logical = false
        Outcome (1,:) char = ''
        Results (1,1) struct = struct()
    end

    properties (Constant)
        REQUIRED = ["TrialDelivery" "ManualTrigger" "SpoofTrough" "InTrial" "DelayPeriod" "RespWindow" "Depth"]
        PERIOD = 0.05                            % how often the subject looks at the trial state (s)
        STALL_RECOVER = 20                       % s without a trial before it steps off, visits the trough, steps on
        STALL_GIVE_UP = 150                      % s without a trial before the session is stopped
    end

    properties (Constant, Access = private)
        % scheduled actions
        A_ON = 1                                 % step onto the platform
        A_RESPOND = 2                            % leave it, if the response window is open
        A_ABORT = 3                              % leave it, if the delay is still running
        A_OFF = 4                                % leave it
        A_TROUGH = 5                             % enter the trough
        % log codes (Results.Log, column 3)
        L_STATE = 1                              % [InTrial DelayPeriod RespWindow] changed
        L_DONE = 2                               % a trial completed
        L_WINDOW = 10                            % the window opened: [type depth pYes]
        L_RESPOND = 11
        L_ABORT = 20
        L_TROUGH = 21
        L_OFF = 22
        L_ON = 23
        L_RECOVER = 30
    end

    properties (Access = private)
        Timer_
        T0_
        Ready_ (1,1) logical = false
        P_                                       % parameters by valid name, triggers included
        TTcol_ (1,1) double = NaN                % TrialType's column in the trial table
        Stream_
        Last_ (1,3) logical = [false false false]   % InTrial, DelayPeriod, RespWindow
        OnPlatform_ (1,1) logical = false
        Queue_ (:,2) double = zeros(0, 2)        % [time action]
        Responded_ (1,1) logical = false
        TrialType_ (1,1) double = NaN
        LastDone_ (1,1) double = 0
        LastProgress_ (1,1) double = 0
        LastRecover_ (1,1) double = 0
        Profiling_ (1,1) logical = false
        Profile_ = []
        TimedAt_ (1,1) double = NaN              % when the timed trials were done (s)
        Log_ (:,6) double = nan(60000, 6)        % [time done code a b c]
        NLog_ (1,1) double = 0
        Meta_ (1,1) struct = struct()
    end

    methods
        function obj = RigPreviewSubject(rx, options)
            arguments
                rx (1,1) epsych.RunExpt
                options.NumTrials (1,1) double {mustBePositive, mustBeInteger} = 250
                options.ProfileTrials (1,1) double {mustBeNonnegative, mustBeInteger} = 0
                options.Threshold (1,1) double = -12
                options.Slope (1,1) double {mustBePositive} = 3
                options.FalseAlarmRate (1,1) double {mustBeInRange(options.FalseAlarmRate, 0, 1)} = 0.10
                options.LapseRate (1,1) double {mustBeInRange(options.LapseRate, 0, 1)} = 0.03
                options.AbortRate (1,1) double {mustBeInRange(options.AbortRate, 0, 1)} = 0.07
                options.Seed (1,1) double = 1
                options.MaxSeconds (1,1) double {mustBePositive} = 3600
            end
            obj.RX = rx;
            for f = string(fieldnames(options))'
                obj.(f) = options.(f);
            end
            % A stream of its own: the trial selector may be drawing from the
            % global one.
            obj.Stream_ = RandStream('mt19937ar', 'Seed', obj.Seed);
        end

        function start(obj)
            % start(obj)
            % Begin: the first tick turns trial delivery on and steps onto
            % the platform. Call once the session is RUNNING.
            obj.T0_ = tic;
            obj.Timer_ = timer('Name', 'RigPreviewSubject', 'ExecutionMode', 'fixedSpacing', ...
                'Period', obj.PERIOD, 'BusyMode', 'drop', 'TimerFcn', @(~,~) obj.tick_());
            start(obj.Timer_);
        end

        function delete(obj)
            if ~isempty(obj.Timer_) && isvalid(obj.Timer_)
                stop(obj.Timer_);
                delete(obj.Timer_);
            end
        end
    end

    methods (Access = private)
        function tick_(obj)
            if obj.Finished, return; end
            try
                obj.step_();
            catch ME
                % A failure here must still stop the session and idle the
                % hardware, or the rig is left delivering trials to nobody.
                vprintf(0, 1, ME);
                obj.finish_(['error: ' ME.message]);
            end
        end

        function step_(obj)
            R = obj.RX.RUNTIME;
            t = toc(obj.T0_);
            if ~obj.Ready_
                obj.prepare_(R, t);
                return
            end

            nDone = R.TRIALS(1).TrialIndex - 1;
            cur = [obj.isOn_(obj.P_.InTrial), obj.isOn_(obj.P_.DelayPeriod), obj.isOn_(obj.P_.RespWindow)];
            if any(cur ~= obj.Last_)
                obj.log_(t, nDone, obj.L_STATE, cur(1), cur(2), cur(3));
            end

            % The trial's delay began: will this subject leave early?
            if cur(2) && ~obj.Last_(2)
                obj.Responded_ = false;
                obj.TrialType_ = R.TRIALS(1).trials{R.TRIALS(1).NextTrialID, obj.TTcol_};
                if rand(obj.Stream_) < obj.AbortRate
                    obj.schedule_(t + 0.10 + 0.25 * rand(obj.Stream_), obj.A_ABORT);
                end
            end

            % The response window opened: does it respond?
            if cur(3) && ~obj.Last_(3)
                obj.TrialType_ = R.TRIALS(1).trials{R.TRIALS(1).NextTrialID, obj.TTcol_};
                depth = double(obj.P_.Depth.Value);
                switch obj.TrialType_
                    case 0
                        pYes = obj.FalseAlarmRate + (1 - obj.FalseAlarmRate - obj.LapseRate) ...
                            * normcdf((depth - obj.Threshold) / obj.Slope);
                    case 1
                        pYes = obj.FalseAlarmRate;
                    otherwise
                        pYes = 1 - obj.LapseRate;      % a reminder is at full depth
                end
                if obj.OnPlatform_ && rand(obj.Stream_) < pYes
                    obj.schedule_(t + 0.15 + 0.40 * rand(obj.Stream_), obj.A_RESPOND);
                end
                obj.log_(t, nDone, obj.L_WINDOW, obj.TrialType_, depth, pYes);
            end

            % The window closed with the subject still on the platform. On a
            % catch trial that is a correct reject: the pellet is in the
            % trough and the trial completes when the subject collects it.
            if ~cur(3) && obj.Last_(3) && ~obj.Responded_ && obj.OnPlatform_ ...
                    && obj.TrialType_ == 1 && nDone == obj.LastDone_
                obj.schedule_(t + 0.30 + 0.30 * rand(obj.Stream_), obj.A_OFF);
                obj.schedule_(t + 0.90 + 0.30 * rand(obj.Stream_), obj.A_TROUGH);
            end

            obj.act_(t, nDone, cur);
            obj.Last_ = cur;

            if nDone > obj.LastDone_
                obj.completed_(t, nDone);
            end

            % Nothing has completed for a while: step off, visit the trough,
            % step back on. Covers a state this model did not foresee.
            stalled = t - obj.LastProgress_;
            if stalled > obj.STALL_RECOVER && t - obj.LastRecover_ > obj.STALL_RECOVER
                obj.LastRecover_ = t;
                obj.Queue_ = zeros(0, 2);
                obj.schedule_(t, obj.A_OFF);
                obj.schedule_(t + 0.4, obj.A_TROUGH);
                obj.schedule_(t + 1.5, obj.A_ON);
                obj.log_(t, nDone, obj.L_RECOVER, cur(1), cur(2), cur(3));
                vprintf(1, 'RigPreviewSubject: no trial for %.0f s (trial %d); stepping off, to the trough, and back on', ...
                    stalled, nDone + 1)
            end

            if nDone >= obj.NumTrials + obj.ProfileTrials
                obj.finish_('complete');
            elseif stalled > obj.STALL_GIVE_UP
                obj.finish_(sprintf('stalled after %d trials', nDone));
            elseif t > obj.MaxSeconds
                obj.finish_(sprintf('time limit after %d trials', nDone));
            end
        end

        function prepare_(obj, R, t)
            % As gui.BehaviorGUI resolves them: RUNTIME.P leaves triggers out.
            obj.P_ = R.all_parameters(asStruct=true, includeTriggers=true);
            missing = obj.REQUIRED(~isfield(obj.P_, obj.REQUIRED));
            assert(isempty(missing), 'RigPreviewSubject:MissingParameter', ...
                'This session has no parameter named %s. The simulated subject drives the appetitive platform circuit.', ...
                strjoin(missing, ', '));
            obj.TTcol_ = R.TRIALS(1).writeParamIdx.TrialType;

            % Trial-loop timing, without touching the EPsych/TickStats
            % preference: PsychTimerRunTime reads this property every tick.
            R.TickStats = epsych.TickStats(Period = R.TIMER.Period);

            I = R.Interfaces;
            obj.Meta_.TimerPeriod = R.TIMER.Period;
            obj.Meta_.Interfaces = arrayfun(@(x) string(class(x)), I);
            obj.Meta_.DeferralEnabled = R.EVENTS.DeferralEnabled;
            obj.Meta_.RecordBuffers = R.RecordBuffers;
            obj.Meta_.RecordStimulusSettings = R.RecordStimulusSettings;
            obj.Meta_.SkipUnchangedWrites = arrayfun(@(x) x.SkipUnchangedWrites, I);
            obj.Meta_.SkipUnchangedStimulus = arrayfun(@(x) x.SkipUnchangedStimulus, I);
            obj.Meta_.NumParameters = numel(fieldnames(obj.P_));

            obj.P_.TrialDelivery.Value = true;
            obj.platform_(t, true);
            obj.LastProgress_ = t;
            obj.LastRecover_ = t;
            obj.Ready_ = true;
        end

        function act_(obj, t, nDone, cur)
            % Carry out the scheduled actions that are due.
            due = obj.Queue_(:, 1) <= t;
            acts = obj.Queue_(due, 2);
            obj.Queue_ = obj.Queue_(~due, :);
            for k = 1:numel(acts)
                switch acts(k)
                    case obj.A_ON
                        obj.platform_(t, true);
                    case obj.A_OFF
                        obj.platform_(t, false);
                    case obj.A_RESPOND
                        if cur(3) && obj.OnPlatform_
                            obj.platform_(t, false);
                            obj.Responded_ = true;
                            obj.log_(t, nDone, obj.L_RESPOND, obj.TrialType_, 0, 0);
                            if obj.TrialType_ ~= 1
                                % a hit puts a pellet in the trough
                                obj.schedule_(t + 0.45 + 0.20 * rand(obj.Stream_), obj.A_TROUGH);
                            end
                        end
                    case obj.A_ABORT
                        if cur(2) && obj.OnPlatform_
                            obj.platform_(t, false);
                            obj.Responded_ = true;
                            obj.log_(t, nDone, obj.L_ABORT, obj.TrialType_, 0, 0);
                        end
                    case obj.A_TROUGH
                        obj.P_.SpoofTrough.Trigger();
                        obj.log_(t, nDone, obj.L_TROUGH, 0, 0, 0);
                end
            end
        end

        function completed_(obj, t, nDone)
            obj.log_(t, nDone, obj.L_DONE, 0, 0, 0);
            obj.LastDone_ = nDone;
            obj.LastProgress_ = t;
            obj.LastRecover_ = t;
            % Drop what belonged to the finished trial; a trough visit still
            % to come is kept.
            obj.Queue_ = obj.Queue_(obj.Queue_(:, 2) == obj.A_TROUGH, :);
            if ~obj.OnPlatform_
                obj.schedule_(t + 1.0 + 0.8 * rand(obj.Stream_), obj.A_ON);
            end
            if mod(nDone, 25) == 0
                vprintf(1, 'RigPreviewSubject: %d trials at %.0f s', nDone, t)
            end
            if nDone >= obj.NumTrials && isnan(obj.TimedAt_)
                obj.TimedAt_ = t;
                if obj.ProfileTrials > 0
                    profile clear
                    profile on
                    obj.Profiling_ = true;
                    vprintf(1, 'RigPreviewSubject: profiler on for %d more trials', obj.ProfileTrials)
                end
            end
        end

        function platform_(obj, t, tf)
            obj.P_.ManualTrigger.Value = tf;
            obj.OnPlatform_ = tf;
            if tf, code = obj.L_ON; else, code = obj.L_OFF; end
            obj.log_(t, obj.LastDone_, code, 0, 0, 0);
        end

        function schedule_(obj, when, action)
            obj.Queue_(end+1, :) = [when action];
        end

        function finish_(obj, outcome)
            % Whatever happens below, the driver waiting on Finished must be
            % released.
            released = onCleanup(@() obj.release_());
            obj.Outcome = outcome;
            elapsed = toc(obj.T0_);
            stop(obj.Timer_);
            if obj.Profiling_
                profile off
                obj.Profile_ = profile('info');
                obj.Profiling_ = false;
            end
            vprintf(1, 'RigPreviewSubject: finishing (%s) at %.0f s', outcome, elapsed)
            if obj.Ready_
                obj.P_.TrialDelivery.Value = false;
                obj.P_.ManualTrigger.Value = false;
            end
            % Stop the session as the window's Stop control does.
            obj.RX.halt();
            obj.collect_(elapsed);
            clear released
        end

        function release_(obj)
            obj.Finished = true;
        end

        function collect_(obj, elapsed)
            R = obj.RX.RUNTIME;
            S = struct();
            S.Outcome = obj.Outcome;
            S.Elapsed = elapsed;
            S.TimedSeconds = obj.TimedAt_;
            S.NumTimed = obj.NumTrials;
            S.NumProfiled = obj.ProfileTrials;
            S.Meta = obj.Meta_;
            S.Subject = struct('Threshold', obj.Threshold, 'Slope', obj.Slope, ...
                'FalseAlarmRate', obj.FalseAlarmRate, 'LapseRate', obj.LapseRate, ...
                'AbortRate', obj.AbortRate, 'Seed', obj.Seed);
            S.Log = obj.Log_(1:obj.NLog_, :);
            S.NumTrials = 0;

            ts = R.TickStats;
            if ~isempty(ts)
                T = ts.phaseTable();
                S.PhaseNames = string(T.Properties.VariableNames);
                S.Phase = table2array(T);
                S.TickSummary = ts.summary();
            end
            S.Ticks = bench_rig_tick('dump');

            if isfield(R.TRIALS, 'DATA') && ~isempty(R.TRIALS(1).DATA)
                D = R.TRIALS(1).DATA;
                S.NumTrials = numel(D);
                keep = intersect(["RespCode" "TrialType" "Depth" "StimDelay" "RespLatency" "PelletTotal"], ...
                    string(fieldnames(D))', 'stable');
                for f = keep
                    S.Data.(f) = double([D.(f)]);
                end
                S.Data.Time = [D.computerTimestamp];
            end

            if ~isempty(obj.Profile_)
                S.Profile = RigPreviewSubject.reduceProfile_(obj.Profile_);
            end
            obj.Results = S;
        end

        function log_(obj, t, nDone, code, a, b, c)
            k = obj.NLog_ + 1;
            if k > size(obj.Log_, 1), return; end
            obj.Log_(k, :) = [t nDone code a b c];
            obj.NLog_ = k;
        end
    end

    methods (Static, Access = private)
        function tf = isOn_(p)
            v = p.Value;
            tf = isscalar(v) && (isnumeric(v) || islogical(v)) && ~isnan(v) && v ~= 0;
        end

        function F = reduceProfile_(info)
            % The 300 costliest functions: totals, self time, and -- for the
            % toolbox's own files -- the time on each line.
            T = info.FunctionTable;
            [~, ix] = sort([T.TotalTime], 'descend');
            T = T(ix(1:min(300, numel(ix))));
            root = fileparts(fileparts(mfilename('fullpath')));
            F = struct('FunctionName', {T.FunctionName}, 'FileName', {T.FileName}, ...
                'TotalTime', {T.TotalTime}, 'NumCalls', {T.NumCalls}, 'SelfTime', 0, 'Lines', []);
            for k = 1:numel(T)
                ch = T(k).Children;
                F(k).SelfTime = T(k).TotalTime;
                if ~isempty(ch)
                    F(k).SelfTime = T(k).TotalTime - sum([ch.TotalTime]);
                end
                if startsWith(T(k).FileName, root, 'IgnoreCase', true)
                    F(k).Lines = T(k).ExecutedLines;     % [line calls seconds]
                end
            end
        end
    end
end
