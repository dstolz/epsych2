classdef TickStats < handle
    % S = epsych.TickStats()
    % S = epsych.TickStats(Period=0.01, TickCapacity=200000)
    % Timing of the trial loop, recorded only when a session asks for it.
    %
    % The trial loop shares one MATLAB thread with every GUI timer, listener
    % and redraw, and nothing recorded how long a tick or a trial boundary
    % took, so an overrun was invisible. This keeps two things:
    %
    %   * every TICK's duration (a ring, so a long session costs fixed memory)
    %   * every TRIAL BOUNDARY, split into the phases named in PHASES -- the
    %     time between a trial being found complete and the next one having
    %     been dispatched, which is dead time the subject waits through.
    %
    % It is OFF unless asked for. epsych.Runtime.TickStats is empty by default
    % and every call site tests isempty first, so a session that does not want
    % timing pays one isempty per tick. RunExpt creates one at Run when the
    % preference EPsych/TickStats is true (epsych.TickStats.enabledByPref), and
    % reports it at Stop. A script creates one itself:
    %
    %   RUNTIME.TickStats = epsych.TickStats(Period=0.01);
    %
    % Properties:
    %   Period     - nominal timer period (s); a tick longer than this is an overrun
    %   NumTicks   - ticks recorded
    %   NumTrials  - trial boundaries recorded
    %   Overruns   - ticks that took longer than Period
    %
    % Methods:
    %   tickBegin / tickEnd       - bracket one timer tick
    %   boundaryBegin             - a trial was found complete
    %   mark(phase)               - the named phase just ended
    %   boundaryEnd               - the next trial has been dispatched
    %   summary                   - struct of medians, 95th percentiles and maxima (ms)
    %   report                    - log the summary (vprintf level 1)
    %   tickDurations / phaseTable - the raw numbers
    %
    % Nothing here throws into the trial loop: a mark for a phase that is not
    % in PHASES, or a mark with no boundary open, is ignored.
    %
    % See also: ep_TimerFcn_RunTime, epsych.Runtime.dispatchNextTrial,
    %           documentation/epsych/epsych_TickStats.md

    properties (Constant)
        % Boundary phases, in the order the loop reaches them.
        %   sweep      read every readable parameter into the trial record
        %   journal    append the record to the trial journal
        %   onComplete selector.onComplete
        %   newData    every NewData listener (analysis and displays)
        %   recompile  a pending operator recompile, when there is one
        %   select     selector.selectNext
        %   reset      the ResetTrig pulse
        %   writes     the per-trial parameter writes
        %   trigger    the NewTrial pulse -- the next trial starts when it ends
        %   render     deferred display work flushed after the trigger
        %   newTrial   every NewTrial listener
        PHASES = ["sweep" "journal" "onComplete" "newData" "recompile" ...
                  "select" "reset" "writes" "trigger" "render" "newTrial"]

        % The phases up to and including "trigger" are time the subject waits.
        LAST_WAITED_PHASE = "trigger"
    end

    properties
        Period (1,1) double = NaN
    end

    properties (SetAccess = private)
        NumTicks  (1,1) double = 0
        NumTrials (1,1) double = 0
        Overruns  (1,1) double = 0
    end

    properties (Access = private)
        tickRing_  (:,1) single
        tickTic_   = []
        phase_     (:,:) single    % NumTrials x numel(PHASES), seconds
        bTic_      = []            % start of the open boundary
        lastTic_   = []            % last mark inside the open boundary
        row_       (1,1) double = 0
    end

    methods
        function obj = TickStats(options)
            arguments
                options.Period (1,1) double = NaN
                options.TickCapacity (1,1) double {mustBePositive, mustBeInteger} = 200000
                options.TrialCapacity (1,1) double {mustBePositive, mustBeInteger} = 2000
            end
            obj.Period = options.Period;
            obj.tickRing_ = nan(options.TickCapacity, 1, 'single');
            obj.phase_ = nan(options.TrialCapacity, numel(obj.PHASES), 'single');
        end

        function tickBegin(obj)
            obj.tickTic_ = tic;
        end

        function tickEnd(obj)
            if isempty(obj.tickTic_), return; end
            d = toc(obj.tickTic_);
            obj.tickTic_ = [];
            obj.NumTicks = obj.NumTicks + 1;
            obj.tickRing_(mod(obj.NumTicks - 1, numel(obj.tickRing_)) + 1) = d;
            if d > obj.Period
                obj.Overruns = obj.Overruns + 1;
            end
        end

        function boundaryBegin(obj)
            obj.NumTrials = obj.NumTrials + 1;
            obj.row_ = obj.NumTrials;
            if obj.row_ > size(obj.phase_, 1)
                % Doubling keeps the amortized cost flat for a session longer
                % than anyone planned for.
                obj.phase_(2 * size(obj.phase_, 1), end) = 0;
                obj.phase_(obj.row_:end, :) = NaN;
            end
            obj.bTic_ = tic;
            obj.lastTic_ = obj.bTic_;
        end

        function mark(obj, phase)
            % mark(obj, phase)
            % The named phase just ended; charge it the time since the
            % previous mark. A phase reached twice in one boundary adds up.
            if isempty(obj.lastTic_) || obj.row_ == 0, return; end
            k = find(obj.PHASES == phase, 1);
            if isempty(k), return; end
            d = toc(obj.lastTic_);
            obj.lastTic_ = tic;
            prev = obj.phase_(obj.row_, k);
            if isnan(prev), prev = 0; end
            obj.phase_(obj.row_, k) = prev + d;
        end

        function boundaryEnd(obj)
            obj.bTic_ = [];
            obj.lastTic_ = [];
        end

        function d = tickDurations(obj)
            % d = tickDurations(obj)
            % Recorded tick durations in seconds, oldest first (the newest
            % TickCapacity of them when the ring has wrapped).
            n = min(obj.NumTicks, numel(obj.tickRing_));
            if obj.NumTicks <= numel(obj.tickRing_)
                d = double(obj.tickRing_(1:n));
            else
                k = mod(obj.NumTicks, numel(obj.tickRing_));
                d = double([obj.tickRing_(k+1:end); obj.tickRing_(1:k)]);
            end
        end

        function T = phaseTable(obj)
            % T = phaseTable(obj)
            % One row per trial boundary, one variable per phase, in seconds.
            % NaN where a boundary never reached a phase.
            T = array2table(double(obj.phase_(1:obj.NumTrials, :)), ...
                'VariableNames', cellstr(obj.PHASES));
        end

        function S = summary(obj)
            % S = summary(obj)
            % Medians, 95th percentiles and maxima, in milliseconds.
            %
            % Returns a struct with fields:
            %   NumTicks, NumTrials, Overruns, Period_ms
            %   Tick     - struct Median, P95, Max (ms)
            %   Phase    - table: Phase, N, Median, P95, Max (ms)
            %   Waited   - struct Median, P95, Max (ms): trial found complete
            %              to the end of the NewTrial pulse
            %   Boundary - the same over every phase
            S = struct();
            S.NumTicks = obj.NumTicks;
            S.NumTrials = obj.NumTrials;
            S.Overruns = obj.Overruns;
            S.Period_ms = obj.Period * 1e3;
            S.Tick = epsych.TickStats.stats_(obj.tickDurations() * 1e3);

            P = double(obj.phase_(1:obj.NumTrials, :)) * 1e3;
            n = numel(obj.PHASES);
            N = zeros(n, 1); med = nan(n, 1); p95 = nan(n, 1); mx = nan(n, 1);
            for k = 1:n
                v = P(:, k);
                v = v(~isnan(v));
                N(k) = numel(v);
                s = epsych.TickStats.stats_(v);
                med(k) = s.Median; p95(k) = s.P95; mx(k) = s.Max;
            end
            S.Phase = table(obj.PHASES(:), N, med, p95, mx, ...
                'VariableNames', {'Phase', 'N', 'Median', 'P95', 'Max'});

            last = find(obj.PHASES == obj.LAST_WAITED_PHASE, 1);
            S.Waited = epsych.TickStats.stats_(sum(P(:, 1:last), 2, 'omitnan'));
            S.Boundary = epsych.TickStats.stats_(sum(P, 2, 'omitnan'));
        end

        function report(obj)
            % report(obj)
            % Log the summary at level 1, one record per line.
            if obj.NumTicks == 0 && obj.NumTrials == 0
                vprintf(1, 'Trial-loop timing: nothing was recorded')
                return
            end
            S = obj.summary();
            vprintf(1, ['Trial-loop timing: %d ticks, median %.2f ms, 95%% %.2f ms, ' ...
                'max %.1f ms, %d over the %.1f ms period'], ...
                S.NumTicks, S.Tick.Median, S.Tick.P95, S.Tick.Max, S.Overruns, S.Period_ms)
            if S.NumTrials == 0, return; end
            vprintf(1, ['Trial boundary over %d trials: subject waited median %.1f ms, ' ...
                '95%% %.1f ms, max %.1f ms (whole boundary median %.1f ms)'], ...
                S.NumTrials, S.Waited.Median, S.Waited.P95, S.Waited.Max, S.Boundary.Median)
            for k = 1:height(S.Phase)
                if S.Phase.N(k) == 0, continue; end
                vprintf(1, '  %-10s median %7.2f ms   95%% %7.2f ms   max %7.1f ms   (n=%d)', ...
                    S.Phase.Phase(k), S.Phase.Median(k), S.Phase.P95(k), S.Phase.Max(k), S.Phase.N(k))
            end
        end
    end

    methods (Static)
        function tf = enabledByPref()
            % tf = epsych.TickStats.enabledByPref()
            % True when preference EPsych/TickStats is set and true. Read
            % behind ispref: getpref with a default CREATES a missing pref.
            tf = false;
            try
                if ispref('EPsych', 'TickStats')
                    tf = logical(getpref('EPsych', 'TickStats'));
                    tf = isscalar(tf) && tf;
                end
            catch
                tf = false;
            end
        end
    end

    methods (Static, Access = private)
        function s = stats_(v)
            v = v(~isnan(v));
            if isempty(v)
                s = struct('Median', NaN, 'P95', NaN, 'Max', NaN);
                return
            end
            s = struct('Median', median(v), 'P95', prctile(v, 95), 'Max', max(v));
        end
    end
end
