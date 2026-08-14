function results = checkTimer(self)
% results = checkTimer(self)
% Run a throwaway timer configured exactly like the PsychTimer and measure
% what the machine actually delivers. Timer jitter is invisible until trials
% start dropping, and it varies with machine load, so measuring it is the
% only way to know.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, epsych.RunExpt.CreateTimer
arguments
    self
end

GROUP = "Timer";
results = epsych.SelfTest.result();

% Deliberately NOT 'PsychTimer': epsych.RunExpt.CreateTimer and
% ExptDispatch("Stop") both find-and-delete timers by that name, so reusing it
% would let a self-test destroy a live session's timer.
TIMER_NAME = 'PsychTimerSelfTest';
MAX_TICKS  = 100;

if ~isempty(self.RunExpt) && isvalid(self.RunExpt) && self.RunExpt.STATE >= PRGMSTATE.RUNNING
    results = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "skip", ...
        'A session is running; an extra timer would compete with the trial loop.');
    return
end

period = 0.01;
if ~isempty(self.RunExpt) && isvalid(self.RunExpt) ...
        && isfield(self.RunExpt.FUNCS, 'TimerPeriod') && ~isempty(self.RunExpt.FUNCS.TimerPeriod)
    period = self.RunExpt.FUNCS.TimerPeriod;
end
if ~isnumeric(period) || ~isscalar(period) || period < 0.001 || period > 1
    results = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "skip", ...
        'Timer period is invalid; see the Functions group.');
    return
end

nTicks = min(MAX_TICKS, max(20, ceil(1 / period)));

t = tic;

% Clean up any timer this check left behind previously.
stale = timerfindall('Name', TIMER_NAME);
if ~isempty(stale)
    stop(stale);
    delete(stale);
end

tickTimes = nan(1, nTicks);
tickCount = 0;
startTic  = [];

T = timer('BusyMode', 'drop', ...
    'ExecutionMode', 'fixedSpacing', ...
    'Name', TIMER_NAME, ...
    'Period', period, ...
    'TasksToExecute', nTicks, ...
    'StartFcn', @(~,~) localOnStart(), ...
    'TimerFcn', @(~,~) localOnTick());
cleanupTimer = onCleanup(@() localCleanup(T));

try
    start(T);
    wait(T);
catch ME
    vprintf(0, 1, ME);
    results = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "fail", ...
        sprintf('The timer could not be started or run: %s', ME.message), ...
        Remedy = "Check for a MATLAB timer error; try `delete(timerfindall)` and retry.");
    return
end

elapsed = toc(t);

observed = tickTimes(1:tickCount);
if tickCount < 2
    results = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "fail", ...
        sprintf('The timer produced only %d tick(s) out of %d.', tickCount, nTicks), ...
        Remedy = "MATLAB timers are not firing; restart MATLAB.");
    return
end

intervals = diff(observed);

% The verdict uses the median, not the mean: one long stall (a garbage
% collection, another application grabbing the CPU) would otherwise drag the
% mean far enough to condemn a machine that is actually fine. The stall is
% still reported separately, because it is its own kind of problem.
medianPeriod = median(intervals);
meanPeriod   = mean(intervals);
maxInterval  = max(intervals);
maxJitter    = max(abs(intervals - period));
droppedPct   = 100 * (nTicks - tickCount) / nTicks;
overrunPct   = 100 * (medianPeriod - period) / period;
stallFactor  = maxInterval / period;

detail = [ ...
    sprintf("Requested period: %.4f s", period), ...
    sprintf("Measured median:  %.4f s (%+.1f%%)", medianPeriod, overrunPct), ...
    sprintf("Measured mean:    %.4f s", meanPeriod), ...
    sprintf("Longest interval: %.4f s (%.1fx the period)", maxInterval, stallFactor), ...
    sprintf("Max jitter:       %.4f s", maxJitter), ...
    sprintf("Ticks:            %d of %d requested", tickCount, nTicks), ...
    sprintf("Wall time:        %.2f s", elapsed)];

if droppedPct > 0
    r = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "fail", ...
        sprintf('%d of %d ticks did not fire.', nTicks - tickCount, nTicks), ...
        Detail = detail, ...
        Remedy = "Close other MATLAB work and background applications; the trial loop will drop trials at this load.");
elseif overrunPct > 50
    r = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "fail", ...
        sprintf('Timer runs %.0f%% slower than requested (%.4f s vs %.4f s).', overrunPct, medianPeriod, period), ...
        Detail = detail, ...
        Remedy = "This machine cannot sustain the configured period; raise it on the project (Subjects & Projects > Edit Project > Session Defaults) or reduce system load.");
elseif overrunPct > 20
    r = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "warn", ...
        sprintf('Timer runs %.0f%% slower than requested (%.4f s vs %.4f s).', overrunPct, medianPeriod, period), ...
        Detail = detail, ...
        Remedy = "Acceptable, but trial timing will be coarser than the configured period suggests.");
elseif stallFactor > 10
    r = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "warn", ...
        sprintf('Timing is nominal (%.4f s) but one interval stretched to %.3f s.', medianPeriod, maxInterval), ...
        Detail = detail, ...
        Remedy = "Something stalled MATLAB mid-run. A stall this long during a session would delay a trial; check for background load.");
else
    r = epsych.SelfTest.result("C1_TimerSmoke", GROUP, "Timer resolution", "pass", ...
        sprintf('%d ticks at %.4f s (requested %.4f s), max jitter %.4f s.', ...
        tickCount, medianPeriod, period, maxJitter), ...
        Detail = detail);
end

results = epsych.SelfTest.withTime(r, elapsed);

% -----------------------------------------------------------------------
    function localOnStart()
        startTic = tic;
    end

    function localOnTick()
        tickCount = tickCount + 1;
        if tickCount <= numel(tickTimes)
            tickTimes(tickCount) = toc(startTic);
        end
    end
end

% -----------------------------------------------------------------------
function localCleanup(T)
% Stop and delete the probe timer however this check exits.
if isempty(T) || ~isvalid(T)
    return
end
if strcmp(T.Running, 'on')
    stop(T);
end
delete(T);
end
