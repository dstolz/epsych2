classdef OddballSessionDriver < handle
    % D = OddballSessionDriver(RUNTIME, GUI, standardFiles)
    % The scripted operator and subject for smoke_test_oddball_example's
    % live session, run from a TIMER rather than from the test's own loop.
    %
    % Why a timer: on R2024b, top-level code (a script or a function run
    % from the command line) that reads RUNTIME.TRIALS while the session
    % timer is writing RUNTIME.TRIALS(1).DATA(n) -- an indexed assignment
    % through epsych.Runtime's set.TRIALS -- corrupts MATLAB's heap: fields
    % "vanish" ("Unrecognized field name TrialIndex") and MATLAB dies in
    % libut/libmx/libmwlxeutilities with no crash dump, in about half of
    % all sessions. Reading from a callback is safe, because one timer
    % callback never interrupts another. The test loop therefore waits on
    % Done alone; everything that touches the session happens in tick.
    %
    % Each tick: answers the response window (respond to deviants except
    % every 3rd, false-alarm on every 5th standard), pauses once 8 trials
    % are done and checks nothing completes while paused, changes the
    % standard bank at 16, and stops at 40. An exception in tick is kept in
    % Error and ends the drive, so the test can rethrow it.

    properties (SetAccess = private)
        Decided = nan(1, 200)  % 1 responded, 0 withheld, by TrialIndex
        HeldCounts = []        % trials done 1.2 s and 2.2 s into the pause
        BankedAt = []          % TrialIndex when the bank changed
        Paused (1,1) logical = false
        Resumed (1,1) logical = false
        Banked (1,1) logical = false
        Stopped (1,1) logical = false
        Done (1,1) logical = false
        Error = []             % MException raised in tick, if any
    end

    properties (Access = private)
        RUNTIME
        GUI
        StandardFiles
        TTCol = []
        NDev = 0
        NStd = 0
        PauseClock = []        % tic at Pause; [] when not holding
        Timer = []
    end

    methods
        function obj = OddballSessionDriver(RUNTIME, GUI, standardFiles)
            obj.RUNTIME = RUNTIME;
            obj.GUI = GUI;
            obj.StandardFiles = standardFiles;
            obj.Timer = timer(Name = 'OddballSessionDriver', Period = 0.02, ...
                ExecutionMode = 'fixedSpacing', BusyMode = 'drop', ...
                TimerFcn = @(~,~) obj.tick());
            start(obj.Timer);
        end

        function delete(obj)
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
        end
    end

    methods (Access = private)
        function tick(obj)
            if obj.Done, return; end
            try
                obj.step_();
            catch ME
                obj.Error = ME;
                obj.finish_();
            end
        end

        function step_(obj)
            R = obj.RUNTIME;
            G = obj.GUI;
            if ~isvalid(G) || ~strcmp(R.TIMER.Running, 'on')
                obj.finish_();
                return
            end
            if isempty(obj.TTCol)
                obj.TTCol = R.TRIALS(1).writeParamIdx.TrialType;
            end
            nDone = obj.trialsDone_();

            % Holding a pause: let the trial in hand finish, then nothing more.
            if ~isempty(obj.PauseClock)
                t = toc(obj.PauseClock);
                if isscalar(obj.HeldCounts) && t >= 2.2
                    obj.HeldCounts(2) = nDone;
                    G.resumeSession();
                    assert(~G.IsPaused && strcmp(G.PauseButton.Text, 'Pause'), 'Resume did not take')
                    obj.Resumed = true;
                    obj.PauseClock = [];
                elseif isempty(obj.HeldCounts) && t >= 1.2
                    obj.HeldCounts = nDone;
                end
                return
            end

            ti = R.TRIALS(1).TrialIndex;
            if logical(G.RespondButton.Enable) && isnan(obj.Decided(ti))
                isDevNow = R.TRIALS(1).trials{R.TRIALS(1).NextTrialID, obj.TTCol} == 0;
                if isDevNow
                    obj.NDev = obj.NDev + 1;
                    go = mod(obj.NDev, 3) ~= 0;
                else
                    obj.NStd = obj.NStd + 1;
                    go = mod(obj.NStd, 5) == 0;
                end
                obj.Decided(ti) = go;
                if go, G.respond(); end
            end

            if ~obj.Paused && nDone >= 8
                G.pauseSession();
                assert(G.IsPaused && strcmp(G.PauseButton.Text, 'Resume'), 'Pause did not take')
                obj.Paused = true;
                obj.PauseClock = tic;
            elseif ~obj.Banked && nDone >= 16
                G.setBank("standard", obj.StandardFiles(1:2));
                obj.BankedAt = R.TRIALS(1).TrialIndex;
                obj.Banked = true;
            elseif ~obj.Stopped && nDone >= 40
                G.stopSession(Confirm = false);
                obj.Stopped = true;
            end
        end

        function n = trialsDone_(obj)
            % TRIALS has no DATA field until the first trial completes.
            n = 0;
            T = obj.RUNTIME.TRIALS;
            if isfield(T, 'DATA'), n = numel(T(1).DATA); end
        end

        function finish_(obj)
            obj.Done = true;
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
            end
        end
    end
end
