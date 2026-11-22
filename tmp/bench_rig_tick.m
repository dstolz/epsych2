function varargout = bench_rig_tick(RUNTIME, runTimeFcn)
% RUNTIME = bench_rig_tick(RUNTIME)       the session's RunTime timer function
% bench_rig_tick('init', runTimeFcn)      clear the record and name the function to wrap
% S = bench_rig_tick('dump')              what was recorded
% Stamp the start and end of every trial-loop tick of a real session.
%
% tmp/bench_rig_preview.m puts this in the session's FUNCS.TIMERfcn.RunTime
% in place of the function the subject's membership names, and it calls that
% function. epsych.TickStats already times each tick and each boundary phase;
% what it cannot see is the time BETWEEN ticks. After a trial boundary the
% MATLAB thread is held by the graphics that boundary queued, and the next
% tick starts late by that much -- so the gap from a boundary tick's end to
% the next tick's start, less the usual gap, is what the displays cost after
% the callback returned.
%
% The record is kept in persistent arrays written in place: a tick costs two
% toc calls and three scalar writes.
%
% Parameters:
%   RUNTIME    - epsych.Runtime, or the command 'init' or 'dump'.
%   runTimeFcn - with 'init': name of the RunTime function to call each tick.
%
% Returns:
%   RUNTIME - as the wrapped function returned it; or, for 'dump', a struct:
%               n       - ticks recorded
%               tStart  - (n,1) seconds from 'init' at which each tick began
%               tStop   - (n,1) seconds from 'init' at which it ended
%               nDone   - (n,1) trials subject 1 had completed when it ended
%
% See also: bench_rig_preview, bench_rig_report, epsych.TickStats

persistent n tStart tStop nDone t0 fcn

if ischar(RUNTIME) || isstring(RUNTIME)
    switch char(RUNTIME)
        case 'init'
            fcn = char(runTimeFcn);
            n = 0;
            tStart = nan(400000, 1);     % three hours of 25 ms ticks
            tStop = nan(400000, 1);
            nDone = zeros(400000, 1);
            t0 = tic;
        case 'dump'
            varargout{1} = struct('n', n, 'tStart', tStart(1:n), ...
                'tStop', tStop(1:n), 'nDone', nDone(1:n));
    end
    return
end

a = toc(t0);
RUNTIME = feval(fcn, RUNTIME);
b = toc(t0);

if n < numel(tStart)
    n = n + 1;
    tStart(n) = a;
    tStop(n) = b;
    nDone(n) = RUNTIME.TRIALS(1).TrialIndex - 1;
end
varargout{1} = RUNTIME;
end
