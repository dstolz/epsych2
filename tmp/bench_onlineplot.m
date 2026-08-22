function bench_onlineplot()
% bench_onlineplot()
% Measure the OnlinePlot read path: per-parameter .Value against one batched
% get_parameter, and the cost of a full update() tick.
%
% The mock backend has no I/O, so this measures MATLAB-side overhead only --
% the arguments block, the isprop probe, and the IsConnected probe that
% hw.Parameter.get.Value runs before every read. On hw.TDT_RPcox that probe is
% a GetStatus COM call per module, so the real-hardware saving is larger.
%
%   matlab -batch "run('tmp/bench_onlineplot.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here);

nTrace = 10;
nRep = 300;

rt = epsych.Runtime; rt.isTest = true; rt.EVENTS = epsych.EventHub;
iface = BatchProbeInterface();
P = hw.Parameter.empty(1,0);
for i = 1:nTrace
    p = iface.add_parameter(sprintf('Trace%02d',i), 0);
    p.Value = 0;
    iface.put(p,i);
    P(end+1) = p; %#ok<AGROW>
end
rt.Interfaces = iface;

% warm up the JIT
for k = 1:20, v = [P.Value]; v = iface.get_parameter(P,includeInvisible=true); end %#ok<NASGU>

t = tic;
for k = 1:nRep, v = [P.Value]; end %#ok<NASGU>
tPer = toc(t)/nRep;

t = tic;
for k = 1:nRep, v = iface.get_parameter(P,includeInvisible=true); end %#ok<NASGU>
tBatch = toc(t)/nRep;

fprintf('\n%d parameters, %d repetitions\n', nTrace, nRep);
fprintf('  per-parameter [P.Value] : %7.1f us/read-set\n', tPer*1e6);
fprintf('  one batched get_parameter: %7.1f us/read-set\n', tBatch*1e6);
fprintf('  speedup                  : %7.1fx\n', tPer/tBatch);

% full tick, redraw included
f = figure('Visible','off','Tag','BenchOnlinePlot');
ax = axes(f);
op = gui.OnlinePlot(rt,P,ax);
stop(op.h_timer);
if op.startTic_ == 0
    op.h_timer.Timer.StartFcn(op.h_timer.Timer,[]);
end
op.redrawPeriod = 0; % force the draw on every tick

for k = 1:50, op.update(); end   % fill the window
t = tic;
for k = 1:nRep, op.update(); end
tTick = toc(t)/nRep;
nSamp = numel(op.lineH(1).XData);
fprintf('\n  full update() tick, %d traces x %d visible samples: %6.1f us\n', ...
    nTrace, nSamp, tTick*1e6);
fprintf('  (timer period is %g s, so a tick uses %.2f%% of its budget)\n', ...
    op.periodNom, 100*tTick/op.periodNom);

% attribute the tick: sampling alone (paused skips the whole draw)
op.paused = true;
t = tic;
for k = 1:nRep, op.update(); end
tSample = toc(t)/nRep;
op.paused = false;
fprintf('  of which sampling + buffering: %6.1f us, drawing: %6.1f us\n', ...
    tSample*1e6, (tTick-tSample)*1e6);

% one batched set() against the per-line property writes it replaced
L = op.lineH;
xd = L(1).XData;
Y = rand(nTrace, numel(xd));
xc = repmat({xd}, nTrace, 1);

for k = 1:20 %#ok<*NASGU>
    set(L, {'XData','YData'}, [xc, num2cell(Y,2)]);
end
t = tic;
for k = 1:nRep
    set(L, {'XData','YData'}, [xc, num2cell(Y,2)]);
end
tSet = toc(t)/nRep;

t = tic;
for k = 1:nRep
    for i = 1:nTrace
        L(i).XData = xd;
        L(i).YData = Y(i,:);
    end
end
tLoop = toc(t)/nRep;

fprintf('\n  push %d traces x %d samples\n', nTrace, numel(xd));
fprintf('    one batched set()      : %7.1f us\n', tSet*1e6);
fprintf('    2N per-line assignments: %7.1f us\n', tLoop*1e6);
fprintf('    speedup                : %7.1fx\n', tLoop/tSet);

delete(op); close(f);
end
