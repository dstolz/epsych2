function R = bench_trial_boundary(options)
% R = bench_trial_boundary()
% R = bench_trial_boundary(NumWrite=40, NumRead=20, NumControls=20, CallDelay=200e-6)
% What one trial boundary and one idle tick cost, counted and timed, through
% the REAL trial loop (ep_TimerFcn_Start -> ep_TimerFcn_RunTime) against a
% counting stand-in for the device (tmp/CountingProbeInterface.m).
%
% Device calls are COUNTED, so the answer does not depend on this machine:
% the same protocol costs the same number of calls on a rig, where each one
% is a COM round trip. Milliseconds are reported too; with CallDelay = 0 they
% are the MATLAB-side cost alone, and with CallDelay set to a rig's measured
% per-call latency (hw.benchmarkIO) they predict that rig.
%
% The loop is driven from INSIDE A TIMER CALLBACK, as a session drives it.
% That is not a detail: top-level code is interrupted by any running timer
% between statements, while a timer callback is never interrupted by another
% timer -- not even at a pause or a drawnow (measured, R2024b). Timing the
% loop from a script therefore measures something a session never does.
%
% Yields are counted rather than detected: tmp/.yieldspy holds pause.m and
% drawnow.m, which shadow the built-ins while this function has that folder
% on the path. A pause or drawnow inside the boundary is what forces pending
% graphics to render before the next trial starts.
%
% Name=Value options:
%   NumTrials     - trials to run. Default 20
%   NumWrite      - writable scalar parameters on the device. Default 40
%   NumRead       - read-only scalar parameters on the device. Default 20
%   NumExpr       - parameters whose value is an Expression. Default 2
%   NumRoved      - writable parameters with several levels (they change from
%                   trial to trial; the rest are written the same value). Default 2
%   NumControls   - gui.components.Parameter_Control bound to device parameters,
%                   in an invisible figure. Default 0
%   BufferSamples - > 0 adds a readable Buffer of this many samples. Default 0
%   CallDelay     - seconds each device call busy-waits. Default 0
%   ProbeTTL      - seconds the double may cache its connection probe, as
%                   hw.TDT_RPcox does. Default 0.25
%   CoerceSingle  - device keeps numerics in single precision. Default true
%   YieldInTrigger- hold the trigger pulse with pause (yields). Default false
%   Ticks         - idle ticks to count. Default 50
%   Quiet         - no printed report. Default false
%
% Returns a struct:
%   Options        - what was run
%   PerTrial       - table, one row per trial: device calls by kind, Value
%                    reads, log records, and pause/drawnow calls inside the
%                    boundary
%   Trial          - medians of PerTrial
%   PerTick        - struct: device calls and Value reads per idle tick
%   Timing         - epsych.TickStats summary (ms) over the timed trials
%
%   matlab -batch "run('tmp/bench_trial_boundary.m')"
%
% See also: epsych.TickStats, CountingProbeInterface, hw.benchmarkIO

arguments
    options.NumTrials (1,1) double {mustBePositive, mustBeInteger} = 20
    options.NumWrite (1,1) double {mustBeNonnegative, mustBeInteger} = 40
    options.NumRead (1,1) double {mustBeNonnegative, mustBeInteger} = 20
    options.NumExpr (1,1) double {mustBeNonnegative, mustBeInteger} = 2
    options.NumRoved (1,1) double {mustBeNonnegative, mustBeInteger} = 2
    options.NumControls (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    options.BufferSamples (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    options.CallDelay (1,1) double {mustBeNonnegative} = 0
    options.ProbeTTL (1,1) double {mustBeNonnegative} = 0.25
    options.CoerceSingle (1,1) logical = true
    options.YieldInTrigger (1,1) logical = false
    options.Ticks (1,1) double {mustBeNonnegative, mustBeInteger} = 50
    options.Quiet (1,1) logical = false
end

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

scratch = fullfile(tempdir, sprintf('bench_trial_boundary_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

% --- Protocol: one counted device plus the software module -----------------
P = epsych.Protocol(Info = 'bench_trial_boundary');
dev = CountingProbeInterface(CallDelay = 0, CoerceSingle = options.CoerceSingle, ...
    ProbeTTL = options.ProbeTTL, YieldInTrigger = options.YieldInTrigger);
P.addInterface(dev);

W = cell(1, options.NumWrite);
for k = 1:options.NumWrite
    if k <= options.NumRoved
        v = k + [0.1 0.2 0.3];          % several levels: changes trial to trial
    else
        v = 10 * k + 0.1;               % one level: the same value every trial
    end
    W{k} = dev.add_parameter(sprintf('W%03d', k), v);
end
W = [W{:}];
for k = 1:options.NumRead
    p = dev.add_parameter(sprintf('R%03d', k), 0, Access = 'Read');
    dev.put(p, k);
end
for k = 1:options.NumExpr
    p = dev.add_parameter(sprintf('E%03d', k), 0);
    if options.NumWrite >= 1
        ref = sprintf('W%03d', min(options.NumWrite, options.NumRoved + k));
        if mod(k, 2) == 1
            p.Expression = string(ref) + " + 250";
        else
            p.Expression = string(ref) + ".*2";   % a dot operator on purpose
        end
    else
        p.Expression = "Value + 1";
    end
end
if options.BufferSamples > 0
    p = dev.add_parameter('Buf', 0, Type = 'Buffer', Access = 'Read', isArray = true);
    dev.put(p, single(1:options.BufferSamples));
end
for nm = ["x_NewTrial_1" "x_ResetTrig_1" "x_TrialComplete_1"]
    p = dev.add_parameter(char(nm), 0, isTrigger = true);
    dev.put(p, 0);
end

sw = P.SoftwareModule;
sw.add_parameter('SoftA', 1);
sw.add_parameter('SoftB', 2);

P.compile();
assert(P.COMPILED.ntrials > 0, 'bench protocol did not compile');

CONFIG = struct();
CONFIG.PROTOCOL = P;
CONFIG.SUBJECT = struct('Name', 'BenchSubj', 'BoxID', 1);

RUNTIME = epsych.Runtime;
RUNTIME.isTest = true;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(fullfile(scratch, 'bench_session.mat'));
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;
set(RUNTIME.Interfaces, 'mode', hw.DeviceState.Preview);

RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);   % dispatches trial 1

% --- Optional controls, as a behavior GUI would hold ------------------------
ctl = {};
if options.NumControls > 0 && ~isempty(W)
    fig = uifigure('Visible', 'off');
    cleanupFig = onCleanup(@() delete(fig));
    nc = min(options.NumControls, numel(W));
    ctl = cell(1, nc);
    for k = 1:nc
        ctl{k} = gui.components.Parameter_Control(fig, W(k), Type = 'editfield');
    end
end

% --- Counters ---------------------------------------------------------------
sink = CountingLogSink();
L = granary.Logger.instance();
L.addSink(sink);
cleanupSink = onCleanup(@() L.removeSink(sink));

allP = RUNTIME.all_parameters(Access = 'All', includeInvisible = true, includeTriggers = true);
readCount = containers.Map('KeyType', 'char', 'ValueType', 'double');
readCount('n') = 0;
hGet = addlistener(allP, 'Value', 'PostGet', @(~,~) localBump(readCount));
cleanupGet = onCleanup(@() localDelete(hGet));

spyDir = fullfile(here, '.yieldspy');
ws = warning('off', 'MATLAB:dispatcher:nameConflict');
addpath(spyDir);
warning(ws);
cleanupSpy = onCleanup(@() rmpath(spyDir));

dev.CallDelay = options.CallDelay;

% --- Run the loop from inside a timer callback, as a session does -----------
B = containers.Map('KeyType', 'char', 'ValueType', 'any');
ctx = struct('RUNTIME', RUNTIME, 'dev', dev, 'options', options, ...
    'readCount', readCount, 'sink', sink, 'hGet', hGet, 'L', L);
drv = timer('Name', 'BenchDriver', 'ExecutionMode', 'singleShot', 'StartDelay', 0.01, ...
    'TimerFcn', @(~,~) localRun(ctx, B));
start(drv);
wait(drv);
delete(drv);
if isKey(B, 'error')
    rethrow(B('error'));
end

RUNTIME = ep_TimerFcn_Stop(RUNTIME);
delete(RUNTIME);

R = struct();
R.Options = options;
R.PerTrial = B('PerTrial');
R.Trial = B('Trial');
R.PerTick = B('PerTick');
R.Timing = B('Timing');

if ~options.Quiet
    n = options.NumTrials;
    T = R.Trial;
    fprintf('\n=== bench_trial_boundary ===\n');
    fprintf('%d writable (%d roved), %d read-only, %d expression, %d controls, buffer %d, call delay %g us\n', ...
        options.NumWrite, options.NumRoved, options.NumRead, options.NumExpr, ...
        numel(ctl), options.BufferSamples, options.CallDelay * 1e6);
    fprintf('\nPer trial (median of %d):\n', n);
    fprintf('  device calls   %6.0f   (probe %g, read %g, write %g, trigger edges %g, status %g)\n', ...
        T.DeviceCalls, T.Probe, T.Read, T.Write, T.TrigWrite, T.Status);
    fprintf('  writes skipped %6.0f\n', T.Skipped);
    fprintf('  Value reads    %6.0f\n', T.ValueReads);
    fprintf('  log records    %6.0f\n', T.LogRecords);
    fprintf('  pause/drawnow  %6.0f   calls inside the boundary\n', T.Yields);
    if options.Ticks > 0
        K = R.PerTick;
        fprintf('\nPer idle tick: %.2f device calls (probe %.2f, read %.2f, status %.2f), %.2f Value reads\n', ...
            K.DeviceCalls, K.Probe, K.Read, K.Status, K.ValueReads);
    end
    S = R.Timing;
    fprintf('\nTiming over %d trials (ms):\n', S.NumTrials);
    fprintf('  subject waited  median %7.2f   95%% %7.2f   max %7.2f\n', ...
        S.Waited.Median, S.Waited.P95, S.Waited.Max);
    for k = 1:height(S.Phase)
        if S.Phase.N(k) == 0, continue; end
        fprintf('  %-10s      median %7.2f   95%% %7.2f   max %7.2f\n', ...
            S.Phase.Phase(k), S.Phase.Median(k), S.Phase.P95(k), S.Phase.Max(k));
    end
    fprintf('\n');
end

if nargout == 0, clear R; end
end


function localRun(ctx, B)
% The measured body. Runs in a timer callback; an error here would only be
% printed by the timer, so it is carried out in B instead.
try
    RUNTIME = ctx.RUNTIME;
    dev = ctx.dev;
    options = ctx.options;
    readCount = ctx.readCount;
    sink = ctx.sink;

    % Idle ticks: what RunExpt.PsychTimerRunTime does when nothing completed.
    dev.resetCounts(); readCount('n') = 0;
    for k = 1:options.Ticks
        if any(get(RUNTIME.Interfaces, 'mode') == hw.DeviceState.Idle)
            error('bench:idle', 'an interface reported Idle');
        end
        RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
    end
    PerTick = struct('DeviceCalls', NaN, 'Probe', NaN, 'Read', NaN, 'Status', NaN, 'ValueReads', NaN);
    if options.Ticks > 0
        c = dev.Counts;
        PerTick.DeviceCalls = dev.deviceCalls() / options.Ticks;
        PerTick.Probe = c.Probe / options.Ticks;
        PerTick.Read = c.Read / options.Ticks;
        PerTick.Status = c.Status / options.Ticks;
        PerTick.ValueReads = readCount('n') / options.Ticks;
    end

    % Trials, counted.
    n = options.NumTrials;
    vars = {'Probe','Read','Write','Skipped','TrigWrite','Status','DeviceCalls', ...
        'ValueReads','LogRecords','Yields'};
    M = zeros(n, numel(vars));
    for k = 1:n
        dev.resetCounts(); readCount('n') = 0; sink.reset();
        yieldspy_count('reset');
        RUNTIME.TRIALS(1).FORCE_TRIAL = true;
        RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
        c = dev.Counts;
        M(k, :) = [c.Probe, c.Read, c.Write, c.Skipped, c.TrigWrite, c.Status, ...
            dev.deviceCalls(), readCount('n'), sink.Total, yieldspy_count()];
    end
    PerTrial = array2table(M, 'VariableNames', vars);
    Trial = array2table(median(M, 1), 'VariableNames', vars);

    % Trials, timed, with the counters' own overhead out of the way.
    delete(ctx.hGet);
    ctx.L.removeSink(sink);
    RUNTIME.TickStats = epsych.TickStats(Period = 0.01);
    for k = 1:n
        RUNTIME.TickStats.tickBegin();
        RUNTIME.TRIALS(1).FORCE_TRIAL = true;
        RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
        RUNTIME.TickStats.tickEnd();
    end

    B('PerTick') = PerTick;
    B('PerTrial') = PerTrial;
    B('Trial') = Trial;
    B('Timing') = RUNTIME.TickStats.summary();
catch ME
    B('error') = ME;
end
end

function localBump(m)
m('n') = m('n') + 1;
end

function localDelete(h)
try
    h = h(isvalid(h));
    delete(h);
catch
end
end

function localRmdir(d)
try
    if isfolder(d), rmdir(d, 's'); end
catch
end
end
