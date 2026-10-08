classdef Precompute < handle
    % behavior.Precompute  Sessions' results made ahead of time, psignifit fits on background workers.
    %
    % A psignifit fit takes seconds (about 4 s on the standard grid) and
    % everything else about a session milliseconds, so a window that fits
    % on demand stops for every session the first time it is shown. A
    % Precompute makes the results of a list of sessions BEFORE anyone asks:
    % each session is prepared on the MATLAB thread (behavior.Study.prepare:
    % load, staircase, counts -- tens of milliseconds), its psignifit fit is
    % handed to MATLAB's backgroundPool (behavior.fit.Psignifit.submit), and
    % when the fit lands the result is made from the cache (Study.result).
    % Nothing it makes differs from what Study.result would have made: the
    % fit is the same psignifit call on the same input through the same
    % cache, and a session shown while its fit is on a worker waits for that
    % worker rather than fitting twice.
    %
    %   P = behavior.Precompute(S);     % S a behavior.Study
    %   P.run();                        % every visible session; returns when done
    %   P.start();                      % the same in the background, on a timer
    %   P.stop();                       % cancel what is queued and running
    %   delete(P);                      % its timer holds it until then
    %
    % IN THE BACKGROUND (start) a timer gives the queue at most TickBudget
    % seconds of the MATLAB thread every Period, so a window stays usable.
    % A tick does nothing while the Study is making a result for someone
    % else (Study.IsComputing), and starts nothing new while HoldFcn says to
    % hold -- epsych.BehaviorAnalysis holds it while an epsych.RunExpt
    % session runs, as it refuses to scan then; fits already on a worker
    % finish. start() again restarts over a new list: fits still wanted keep
    % running, and fits whose settings, window or file changed are cancelled.
    %
    % WITHOUT A POOL (before R2021b, or Psignifit.override("serial")) fits
    % are made on the MATLAB thread, one per tick, so a window stops for one
    % fit at a time rather than for all of them. A fit a worker failed to
    % make is made on the MATLAB thread too, so the reason recorded is the
    % one a view would show. With the built-in engine nothing is slow:
    % prepare makes every result, several per tick.
    %
    % Properties (read-only):
    %   Study     - the behavior.Study
    %   State     - "idle" | "running" | "held" | "done" | "stopped"
    %   Total     - sessions in the list
    %   Done      - of those, sessions whose result is current
    %   Computed  - of those, the ones made here (the rest already were)
    %   Failed    - sessions whose result could not be made (logged)
    %   Fitting   - psignifit fits on background workers now
    %   Parallel  - fits go to the background pool
    %   Elapsed   - seconds since start or run
    %   LastError - why the last failure failed
    %
    % Properties (settable):
    %   HoldFcn    - @() true while nothing new may start ([] = never hold);
    %                asked at most once a second
    %   Period     - timer period, seconds (default 0.1; read at start)
    %   TickBudget - MATLAB-thread time per tick, seconds (default 0.1)
    %
    % Events: Progress (a count or the state changed), Finished
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.Study.prepare, behavior.fit.Psignifit.submit,
    %   epsych.BehaviorAnalysis

    properties (SetAccess = private)
        Study
        State (1,1) string = "idle"
        Total (1,1) double = 0
        Done (1,1) double = 0
        Computed (1,1) double = 0
        Failed (1,1) double = 0
        Parallel (1,1) logical = false
        LastError (1,1) string = ""
    end

    properties (Dependent)
        Fitting
        Elapsed
    end

    properties
        HoldFcn = []
        Period (1,1) double {mustBePositive} = 0.1
        TickBudget (1,1) double {mustBePositive} = 0.1
    end

    properties (Constant)
        HOLD_CHECK (1,1) double = 1     % seconds between HoldFcn calls
    end

    properties (Access = private)
        Queue_ (1,:) string = strings(1, 0)   % sessions not prepared yet
        Here_ (1,:) string = strings(1, 0)    % sessions to fit on the MATLAB thread
        Jobs_ = struct('SessionKey', {}, 'Job', {})   % fits on workers
        Timer_ = []
        Stepping_ (1,1) logical = false
        Started_ = []
        Held_ (1,1) logical = false
        HoldChecked_ = []
        Announced_ (1,1) string = ""
    end

    events
        Progress
        Finished
    end

    methods
        function obj = Precompute(study)
            % P = behavior.Precompute(study)
            arguments
                study (1,1) behavior.Study
            end
            obj.Study = study;
        end

        function delete(obj)
            % Stop the timer and cancel the fits this object started.
            try
                obj.stopTimer_();
                if ~isempty(obj.Timer_) && isvalid(obj.Timer_)
                    delete(obj.Timer_);
                end
                obj.cancelJobs_(obj.Jobs_);
            catch ME
                vprintf(2, ME);
            end
        end

        function n = get.Fitting(obj)
            n = numel(obj.Jobs_);
        end

        function t = get.Elapsed(obj)
            t = 0;
            if ~isempty(obj.Started_)
                t = toc(obj.Started_);
            end
        end

        % ------------------------------------------------------------------
        function start(obj, keys)
            % start(obj)          every visible session, the checked ones first
            % start(obj, keys)
            % Make these sessions' results in the background. Called again,
            % it restarts over the new list (see the class comment).
            arguments
                obj
                keys (1,:) string = obj.defaultKeys()
            end
            obj.begin_(keys);
            if isempty(obj.Timer_) || ~isvalid(obj.Timer_)
                obj.Timer_ = timer('Name', 'behavior.Precompute', 'ExecutionMode', 'fixedSpacing', ...
                    'Period', obj.Period, 'BusyMode', 'drop', 'TimerFcn', @(~,~) obj.onTick_());
            end
            if strcmp(obj.Timer_.Running, 'off')
                start(obj.Timer_);
            end
        end

        function ok = run(obj, keys, options)
            % ok = run(obj)              every visible session
            % ok = run(obj, keys, Progress = @(k, n) true)
            % Make these sessions' results and return when they are made.
            % HoldFcn is not consulted: this was asked for now. Progress
            % (k = sessions ready + 1) returning false stops it.
            %
            % Returns:
            %   ok - every session's result was made or failed (false when
            %        Progress stopped it)
            arguments
                obj
                keys (1,:) string = obj.defaultKeys()
                options.Progress = []
            end
            obj.stopTimer_();
            obj.begin_(keys);
            while any(obj.State == ["running" "held"])
                obj.step_(false);
                if ~isempty(options.Progress) && ~options.Progress(min(obj.Done + 1, obj.Total), obj.Total)
                    obj.stop();
                    break
                end
                if ~isempty(obj.Jobs_)
                    pause(0.05);    % the workers are fitting: let them, and let a window draw
                end
            end
            ok = obj.State == "done";
        end

        function stop(obj)
            % stop(obj)
            % Forget the queue and cancel this object's fits on the workers.
            obj.stopTimer_();
            obj.cancelJobs_(obj.Jobs_);
            obj.Jobs_ = obj.Jobs_([]);
            obj.Queue_ = strings(1, 0);
            obj.Here_ = strings(1, 0);
            if any(obj.State == ["running" "held"])
                obj.finish_("stopped");
            end
        end

        function step(obj)
            % step(obj)
            % One tick of background work: what the timer calls. Does nothing
            % while the Study is making a result for someone else, and starts
            % nothing new while HoldFcn holds.
            if obj.Stepping_ || ~isvalid(obj.Study) || obj.Study.IsComputing
                return
            end
            obj.step_(true);
        end

        function keys = defaultKeys(obj)
            % keys = defaultKeys(obj)
            % Every visible session, the checked ones first: what the
            % Subject, Compare and Table tabs will ask for.
            keys = obj.Study.visibleKeys();
            first = ismember(localNorm(keys), localNorm(obj.Study.Selection));
            keys = [keys(first) keys(~first)];
        end

        function txt = message(obj)
            % txt = message(obj)
            % One status line saying where it is.
            failed = "";
            if obj.Failed > 0
                failed = sprintf(", %d failed", obj.Failed);
            end
            switch obj.State
                case "running"
                    txt = sprintf("Precomputing: %d of %d session(s) ready", obj.Done, obj.Total);
                    if obj.Fitting > 0
                        txt = txt + sprintf(", %d psignifit fit(s) on background workers", obj.Fitting);
                    end
                    txt = txt + failed + ".";
                case "held"
                    txt = sprintf(['Precomputing waits while a session runs (%d of %d ready); ' ...
                        'fits already started finish.'], obj.Done, obj.Total);
                case "done"
                    txt = sprintf("Precomputed %d session(s) in %s; %d of %d were current already%s.", ...
                        obj.Computed, localDuration(obj.Elapsed), obj.Done - obj.Computed, obj.Total, failed);
                case "stopped"
                    txt = sprintf("Precomputing stopped: %d of %d session(s) ready%s.", obj.Done, obj.Total, failed);
                otherwise
                    txt = "";
            end
        end
    end

    methods (Static)
        function tf = isParallel(settings)
            % tf = behavior.Precompute.isParallel(settings)
            % Whether these settings' fits would go to background workers:
            % fitting on, the psignifit engine, psignifit found, a pool.
            arguments
                settings (1,1) behavior.Settings
            end
            tf = settings.Fit.Enabled && settings.Fit.Engine == "psignifit" ...
                && behavior.fit.Psignifit.available() && behavior.fit.Psignifit.workers() > 0;
        end
    end

    % -----------------------------------------------------------------------
    methods (Access = private)
        function begin_(obj, keys)
            % A fresh list; the fits still wanted keep running.
            keys = unique(keys, 'stable');
            wanted = localNorm(keys);
            keep = false(1, numel(obj.Jobs_));
            for k = 1:numel(obj.Jobs_)
                keep(k) = ismember(localNorm(obj.Jobs_(k).SessionKey), wanted) ...
                    && obj.Study.isCurrentJob(obj.Jobs_(k).Job);
            end
            obj.cancelJobs_(obj.Jobs_(~keep), obj.Jobs_(keep));
            obj.Jobs_ = obj.Jobs_(keep);
            running = localNorm([strings(1, 0) obj.Jobs_.SessionKey]);
            obj.Queue_ = keys(~ismember(wanted, running));
            obj.Here_ = strings(1, 0);
            obj.Total = numel(keys);
            obj.Done = 0;
            obj.Computed = 0;
            obj.Failed = 0;
            obj.LastError = "";
            obj.Parallel = behavior.fit.Psignifit.workers() > 0;
            obj.Started_ = tic;
            obj.Held_ = false;
            obj.HoldChecked_ = [];
            obj.State = "running";
            obj.announce_(true);
        end

        function step_(obj, honourHold)
            if ~any(obj.State == ["running" "held"])
                return
            end
            obj.Stepping_ = true;
            cleanup = onCleanup(@() obj.doneStepping_());

            % Held, not even a finished fit is collected: making its result
            % reads the session file on the thread the trial loop runs on.
            if honourHold && obj.isHeld_()
                if obj.State ~= "held"
                    obj.State = "held";
                    vprintf(2, 'behavior.Precompute: held (a session is running)');
                end
                obj.announce_(false);
                return
            end
            obj.State = "running";
            obj.collect_();

            t0 = tic;
            while toc(t0) < obj.TickBudget
                if ~isempty(obj.Here_)
                    key = obj.Here_(1);
                    obj.Here_(1) = [];
                    obj.makeHere_(key);
                    break           % one fit on the MATLAB thread per tick
                end
                if isempty(obj.Queue_) || (obj.Parallel && obj.Fitting >= behavior.fit.Psignifit.workers())
                    break
                end
                key = obj.Queue_(1);
                obj.Queue_(1) = [];
                if ~obj.prepare_(key)
                    break
                end
            end

            if isempty(obj.Queue_) && isempty(obj.Jobs_) && isempty(obj.Here_)
                obj.finish_("done");
            else
                obj.announce_(false);
            end
            delete(cleanup);
        end

        function more = prepare_(obj, key)
            % One session from the queue; false = this tick has had its time.
            more = true;
            try
                if obj.Study.isCurrent(key)
                    obj.Done = obj.Done + 1;
                    return
                end
                [done, job] = obj.Study.prepare(key);
            catch ME
                obj.fail_(key, string(ME.message));
                return
            end
            if done
                obj.Done = obj.Done + 1;
                obj.Computed = obj.Computed + 1;
                return
            end
            if ~obj.Parallel
                obj.makeHere_(key);
                more = false;
                return
            end
            [~, state] = behavior.fit.Psignifit.submit(job);
            switch state
                case "cached"
                    obj.makeHere_(key);
                case {"submitted" "running"}
                    obj.Jobs_(end+1) = struct('SessionKey', job.SessionKey, 'Job', job);
                otherwise           % "unavailable": the pool went away
                    obj.Parallel = false;
                    obj.makeHere_(key);
                    more = false;
            end
        end

        function collect_(obj)
            % The fits the workers finished: their results, made from the cache.
            for k = numel(obj.Jobs_):-1:1
                J = obj.Jobs_(k);
                [state, msg] = behavior.fit.Psignifit.collect(J.Job);
                if state == "running"
                    continue
                end
                obj.Jobs_(k) = [];
                if ~obj.Study.isCurrentJob(J.Job)
                    % The settings, its window or its file changed while it
                    % was fitted: prepare it again.
                    obj.Queue_(end+1) = J.SessionKey;
                elseif state == "fitted"
                    obj.makeHere_(J.SessionKey);
                else
                    vprintf(2, 'behavior.Precompute: the background fit of %s failed (%s); fitting it on the MATLAB thread', ...
                        J.SessionKey, msg);
                    obj.Here_(end+1) = J.SessionKey;
                end
            end
        end

        function makeHere_(obj, key)
            % The result, on the MATLAB thread: from the cache when a worker
            % made the fit, else fitted here.
            try
                obj.Study.result(key);
                obj.Done = obj.Done + 1;
                obj.Computed = obj.Computed + 1;
            catch ME
                obj.fail_(key, string(ME.message));
            end
        end

        function fail_(obj, key, message)
            obj.Failed = obj.Failed + 1;
            obj.LastError = message;
            vprintf(1, 'behavior.Precompute: %s: %s', key, message);
        end

        function tf = isHeld_(obj)
            if isempty(obj.HoldFcn)
                tf = false;
                return
            end
            if isempty(obj.HoldChecked_) || toc(obj.HoldChecked_) >= obj.HOLD_CHECK
                obj.HoldChecked_ = tic;
                try
                    obj.Held_ = logical(obj.HoldFcn());
                catch ME
                    vprintf(2, 'behavior.Precompute: HoldFcn: %s', ME.message);
                    obj.Held_ = false;
                end
            end
            tf = obj.Held_;
        end

        function cancelJobs_(~, jobs, kept)
            % Cancel these fits, except one another kept job shares (two
            % sessions with identical data share one fit).
            if isempty(jobs)
                return
            end
            if nargin < 3
                kept = jobs([]);
            end
            keptKeys = strings(1, numel(kept));
            for k = 1:numel(kept)
                keptKeys(k) = string(kept(k).Job.Key);
            end
            drop = false(1, numel(jobs));
            for k = 1:numel(jobs)
                drop(k) = ~ismember(string(jobs(k).Job.Key), keptKeys);
            end
            if any(drop)
                behavior.fit.Psignifit.cancel([jobs(drop).Job]);
            end
        end

        function announce_(obj, force)
            % Progress, when something a reader would see has changed.
            sig = sprintf("%s|%d|%d|%d|%d", obj.State, obj.Done, obj.Failed, obj.Fitting, numel(obj.Queue_));
            if force || sig ~= obj.Announced_
                obj.Announced_ = sig;
                notify(obj, 'Progress');
            end
        end

        function finish_(obj, state)
            obj.State = state;
            obj.stopTimer_();
            vprintf(3, 'behavior.Precompute: %s', obj.message());
            obj.announce_(true);
            notify(obj, 'Finished');
        end

        function stopTimer_(obj)
            if ~isempty(obj.Timer_) && isvalid(obj.Timer_) && strcmp(obj.Timer_.Running, 'on')
                stop(obj.Timer_);
            end
        end

        function onTick_(obj)
            % A timer callback that throws stops the timer silently: report,
            % and stop on purpose instead.
            if ~isvalid(obj)
                return
            end
            try
                obj.step();
            catch ME
                vprintf(0, 1, ME);
                obj.LastError = string(ME.message);
                obj.stop();
            end
        end

        function doneStepping_(obj)
            if isvalid(obj)
                obj.Stepping_ = false;
            end
        end
    end
end


% ---------------------------------------------------------------------------
function k = localNorm(keys)
% Keys as they compare (behavior.Catalog.keyEquals's rule).
k = replace(string(keys), "\", "/");
if ispc
    k = lower(k);
end
end


function txt = localDuration(t)
if t < 60
    txt = sprintf("%.1f s", t);
else
    txt = sprintf("%d min %d s", floor(t / 60), round(mod(t, 60)));
end
end
