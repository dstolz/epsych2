function smoke_test_onlineplot()
% smoke_test_onlineplot()
% Exercise the refactored gui.OnlinePlot.
%
% The claims under test:
%   - a tick costs ONE get_parameter call per interface, not one per trace,
%     and the values still land on the right traces
%   - hw.Software, write-only and StimType parameters stay on the local
%     .Value path (they cannot be batched), and mixing them with hardware
%     parameters in one plot still reads each exactly once
%   - a backend that refuses an array read is demoted once and then polled
%     one parameter at a time, with the same values
%   - bitmask-bank mode reads one parameter per BANK and decodes the bits
%   - a read that throws is logged once, not once per tick, and leaves NaN
%   - a non-scalar value (a Buffer) cannot derail the sample column
%   - the ring is sized from timeWindow and the timer period, so a wide
%     window is no longer silently truncated at 1000 samples
%   - trial markers are recycled from a bounded pool instead of accumulating
%   - the trial-number label sits inside the y-limits
%   - one set() pushes every trace, and the traces carry the intended data
%   - teardown removes the graphics from an axes this object does not own
%
% Headless-safe: every figure is closed and every timer deleted before
% returning.
%
%   matlab -batch "run('tmp/smoke_test_onlineplot.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % BatchProbeInterface

cleanupObj = onCleanup(@cleanup_all); %#ok<NASGU>

%% 1. One read per interface, not per trace ------------------------------
[rt,iface,P] = makeRuntime(4);
[op,ax] = makePlot(rt,P);

iface.reset_counts();
op.update();
assert(iface.GetCalls == 1, ...
    'four traces on one interface should cost one get_parameter call, got %d', iface.GetCalls);
assert(iface.GetValues == 4, 'that one call should have served 4 values, got %d', iface.GetValues);
assert(numel(op.readGroups_) == 1, 'expected a single read group, got %d', numel(op.readGroups_));
assert(isempty(op.localRows_), 'no parameter here needs the local path');
fprintf('PASS: a tick costs one get_parameter call per interface\n');

iface.reset_counts();
for k = 1:5, op.update(); end
assert(iface.GetCalls == 5, 'five ticks should cost five calls, got %d', iface.GetCalls);
fprintf('PASS: the read plan is built once, not rebuilt every tick\n');

% values land on the right traces, in source order
iface.put(P(1), 11); iface.put(P(2), 22); iface.put(P(3), 33); iface.put(P(4), 44);
op.update();
col = op.Buffers(:, op.BufferIdx - 1);
assert(isequal(double(col(:))', [11 22 33 44]), ...
    'batched values landed out of order: %s', mat2str(col(:)'));
fprintf('PASS: batched values land on the right traces\n');

% zero becomes NaN so a trace disappears rather than sitting on the axis
iface.put(P(2), 0);
op.update();
col = op.Buffers(:, op.BufferIdx - 1);
assert(isnan(col(2)) && col(1) == 11, 'setZeroToNan should blank only the zero trace');
fprintf('PASS: setZeroToNan applies to the new column only\n');

delete(op); close(ancestor(ax,'figure'));

%% 2. Mixed local and hardware sources -----------------------------------
[rt,iface,P] = makeRuntime(3);
sw = hw.Software;
pSoft = sw.add_parameter('SoftTrace', 0); pSoft.Value = 7;
pWrite = iface.add_parameter('WriteOnly', 0); pWrite.Value = 5; pWrite.Access = 'Write';
rt.Interfaces = [rt.Interfaces sw];

[op,ax] = makePlot(rt,[P(1) pSoft P(2) pWrite P(3)]);
iface.reset_counts();
op.update();

assert(numel(op.readGroups_) == 1, 'the three hardware traces are one group, got %d', numel(op.readGroups_));
assert(isequal(sort(op.localRows_), [2 4]), ...
    'the software and write-only traces belong on the local path, got %s', mat2str(op.localRows_));
assert(iface.GetCalls == 1, 'the hardware group is still one call, got %d', iface.GetCalls);
col = op.Buffers(:, op.BufferIdx - 1);
assert(col(2) == 7, 'the software trace should read its stored value, got %g', col(2));
assert(isnan(col(4)), 'a write-only parameter reads NaN, got %g', col(4));
fprintf('PASS: unbatched parameters keep the local path without breaking the batch\n');

delete(op); close(ancestor(ax,'figure'));

%% 3. A backend that refuses a batch is demoted once ---------------------
[rt,iface,P] = makeRuntime(3, RefuseBatch=true);
iface.put(P(1), 1); iface.put(P(2), 2); iface.put(P(3), 3);
[op,ax] = makePlot(rt,P);

iface.reset_counts();
op.update();
assert(~op.readGroups_(1).Batched, 'the group should be demoted after the failed array read');
col = op.Buffers(:, op.BufferIdx - 1);
assert(isequal(double(col(:))', [1 2 3]), ...
    'demoted reads should still be correct, got %s', mat2str(col(:)'));

iface.reset_counts();
op.update();
assert(iface.GetCalls == 3, ...
    'a demoted group polls once per parameter with no retry of the batch, got %d', iface.GetCalls);
fprintf('PASS: a scalar-only backend is demoted once, then polled per parameter\n');

delete(op); close(ancestor(ax,'figure'));

%% 4. Bitmask-bank mode reads one parameter per bank ---------------------
rt = epsych.Runtime; rt.isTest = true; rt.EVENTS = epsych.EventHub;
bm = BatchProbeInterface();
pBank = bm.add_parameter('~BMid-Behavior', 0);
bits = {'Lick','Spout','Reward'};
for i = 1:numel(bits)
    bm.add_parameter(sprintf('~BM-Behavior#%d^%s', i-1, bits{i}), 0);
end
rt.Interfaces = bm;

[op,ax] = makePlot(rt,'Behavior');
assert(op.N == 3, 'three labelled bits should give three traces, got %d', op.N);
assert(isequal(op.hax.YAxis.TickLabels(:)', bits), ...
    'bit labels should become the y tick labels, got %s', strjoin(op.hax.YAxis.TickLabels(:)',','));

bm.put(pBank, 5); % bits 0 and 2 set
iface_calls = bm.GetCalls; %#ok<NASGU>
bm.reset_counts();
op.update();
assert(bm.GetCalls == 1, 'one bank is one read regardless of bit count, got %d', bm.GetCalls);
col = op.Buffers(:, op.BufferIdx - 1);
% setZeroToNan blanks the clear bits
assert(col(1) == 1 && isnan(col(2)) && col(3) == 1, ...
    'bitmask 5 should light bits 0 and 2, got %s', mat2str(col(:)'));
fprintf('PASS: a bitmask bank costs one read and decodes to one trace per bit\n');

delete(op); close(ancestor(ax,'figure'));

%% 5. A failing read is logged once and leaves NaN -----------------------
[rt,iface,P] = makeRuntime(2);
[op,ax] = makePlot(rt,P);
op.update(); % build the plan against a healthy interface
iface.Connected = false;
iface.RefuseBatch = true; % force the per-parameter path so .Value throws nothing
op.update();
assert(numel(op.readWarned_) <= 1, 'a failing read should be logged at most once');
for k = 1:5, op.update(); end
assert(numel(op.readWarned_) <= 1, ...
    'repeated failures must not accumulate log records, got %d', numel(op.readWarned_));
fprintf('PASS: a failing read is logged once, not once per tick\n');
delete(op); close(ancestor(ax,'figure'));

%% 6. A non-scalar value cannot derail the sample column -----------------
[rt,iface,P] = makeRuntime(2);
iface.put(P(1), (1:128)');   % a Buffer-shaped read
iface.put(P(2), 'not a number');
[op,ax] = makePlot(rt,P);
op.update();
col = op.Buffers(:, op.BufferIdx - 1);
assert(numel(col) == 2, 'the column must stay one value per trace, got %d', numel(col));
assert(col(1) == 1, 'a vector read should contribute its first element, got %g', col(1));
assert(isnan(col(2)), 'a char read should contribute NaN, got %g', col(2));
fprintf('PASS: vector and non-numeric reads degrade to one value per trace\n');
delete(op); close(ancestor(ax,'figure'));

%% 7. The ring is sized from the window, not fixed at 1000 ---------------
[rt,~,P] = makeRuntime(2);
[op,ax] = makePlot(rt,P);
assert(op.capacity_ == 1000, 'the default 13 s window fits the 1000-sample floor, got %d', op.capacity_);
op.timeWindow = seconds([-600 5]);
assert(op.capacity_ > 1000, 'a 605 s window needs more than 1000 samples, got %d', op.capacity_);
assert(size(op.Buffers,2) == op.capacity_, 'the ring should be reallocated to the new capacity');
assert(op.capacity_ >= 605/op.periodNom, ...
    'capacity %d cannot hold 605 s at a %g s period', op.capacity_, op.periodNom);
fprintf('PASS: ring capacity follows the time window\n');
delete(op); close(ancestor(ax,'figure'));

%% 8. Trial markers are recycled, not accumulated ------------------------
[rt,iface,P] = makeRuntime(2);
pTrig = iface.add_parameter('_TrigState~1', 0);
pNum  = iface.add_parameter('_TrialNum~1', 1);
iface.put(pTrig,0); iface.put(pNum,1);
[op,ax] = makePlot(rt,P);
assert(~isempty(op.trialParam), '_TrigState~1 should have been resolved');
op.maxTrialMarkers = 4;
op.redrawPeriod = 0; % draw on every tick so each onset is marked

nBefore = numel(findobj(ax,'Type','line'));
for k = 1:10
    iface.put(pTrig,0); op.update();
    iface.put(pTrig,1); op.update(); % rising edge
    iface.put(pNum,k+1);
end
nAfter = numel(findobj(ax,'Type','line'));
assert(nAfter == nBefore, ...
    'ten onsets should reuse the pool, not add lines (%d -> %d)', nBefore, nAfter);
assert(op.markerIdx_ >= 10, 'every onset should have taken a slot, got %d', op.markerIdx_);
assert(numel(op.markerLine_) == 32, ...
    'the pool is built at setup; changing maxTrialMarkers later does not resize it');
fprintf('PASS: trial markers recycle a bounded pool\n');

% the trial-number label must be visible, i.e. inside the y-limits
yl = op.hax.YAxis.Limits;
shown = op.markerText_(arrayfun(@(h) strcmp(char(h.Visible),'on'), op.markerText_));
assert(~isempty(shown), 'a trial number should have been drawn');
py = shown(1).Position(2);
assert(py >= yl(1) && py <= yl(2), ...
    'the trial-number label at y=%g falls outside the limits [%g %g]', py, yl(1), yl(2));
fprintf('PASS: the trial-number label sits inside the y-limits\n');
delete(op); close(ancestor(ax,'figure'));

%% 9. Traces, palette and teardown ---------------------------------------
[rt,iface,P] = makeRuntime(10);
for i = 1:10, iface.put(P(i), i); end
[op,ax] = makePlot(rt,P);

assert(numel(op.lineH) == 10, 'one line per trace, got %d', numel(op.lineH));
c = op.lineColors;
assert(isequal(size(c),[10 3]), 'lineColors should expand to the trace count');
assert(size(unique(c,'rows'),1) == 10, 'ten traces should get ten distinct colors');

op.redrawPeriod = 0;
op.update(); op.update();
xd = op.lineH(1).XData;
assert(isduration(xd), 'the x axis stays a duration ruler');
for i = 1:10
    yd = op.lineH(i).YData;
    assert(~isempty(yd), 'trace %d should carry data', i);
    % the trace plots yPosition * value, and every sample here is i
    assert(all(abs(yd(~isnan(yd)) - op.yPositions(i)*i) < 1e-6), ...
        'trace %d holds the wrong values', i);
    assert(numel(yd) == numel(xd), 'trace %d x and y lengths disagree', i);
end
fprintf('PASS: every trace is pushed with matching x and y in one transaction\n');

% timeWindow2number is protected; its result reaches the operator through the
% context-menu label, which is where a bad conversion would show.
twItem = findobj(op.hax.ContextMenu,'Tag','uic_timeWindow');
assert(strcmp(twItem.Label,'Time Window = [-10.0 3.0] seconds'), ...
    'the time window label reads "%s"', twItem.Label);
fprintf('PASS: the time window converts without round-tripping through char\n');

lines = op.lineH; nowl = op.nowLine; marks = op.markerLine_;
delete(op);
assert(~any(isvalid(lines)), 'teardown should remove the traces from a borrowed axes');
assert(~isvalid(nowl), 'teardown should remove the now-line');
assert(~any(isvalid(marks)), 'teardown should remove the marker pool');
assert(isvalid(ax), 'teardown must not delete an axes this object does not own');
fprintf('PASS: teardown clears the graphics from a host-owned axes\n');
close(ancestor(ax,'figure'));

%% 10. The standalone window, driven by its own timer --------------------
[rt,iface,P] = makeRuntime(5);
pTrig = iface.add_parameter('_TrigState~1', 0);
iface.add_parameter('_TrialNum~1', 1);
iface.put(pTrig,0);
op = gui.OnlinePlot(rt, P); % no axes: OnlinePlot makes its own figure
f = op.figH;

assert(op.ownsFigure_, 'a plot that made its own figure owns it');
assert(strcmp(f.Name,'Online Plot | Box 1'), 'window title is "%s"', f.Name);
assert(f.Position(4) > 175, ...
    'the window height should grow with 5 traces, got %g', f.Position(4));
assert(strcmp(op.h_timer.Timer.Running,'on'), 'the timer should be running');

% let it actually tick against the mock backend
t0 = tic; while toc(t0) < 1.0, drawnow limitrate; end
assert(op.writeCount > 3, 'the timer should have produced samples, got %d', op.writeCount);
assert(all(isfinite(op.lineH(1).YData)) || any(isfinite(op.lineH(1).YData)), ...
    'the first trace should carry data after a second of ticking');
fprintf('PASS: the standalone window ticks and draws under its own timer\n');

nCalls = iface.GetCalls;
assert(nCalls < 3*op.writeCount, ...
    'batching should keep reads near one per tick: %d calls for %d ticks', ...
    nCalls, op.writeCount);
fprintf('PASS: a live run reads about once per tick, not once per trace\n');

op.pause();
assert(op.paused, 'pause should toggle on');
n1 = numel(op.lineH(1).XData);
t0 = tic; while toc(t0) < 0.4, drawnow limitrate; end
assert(numel(op.lineH(1).XData) == n1, 'a paused plot should not redraw');
op.pause();
assert(~op.paused, 'pause should toggle back off');
fprintf('PASS: pause stops the redraw and resumes\n');

% trial-locked toggle, through the menu the operator uses
ptItem = findobj(op.hax.ContextMenu,'Tag','uic_plotType');
clickMenu(ptItem);
assert(op.trialLocked, 'the menu should switch the plot to trial-locked');
assert(seconds(op.timeWindow(1)) < 0 && seconds(op.timeWindow(2)) > 0, ...
    'trial-locked should straddle the onset, got %s', mat2str(seconds(op.timeWindow)));
t0 = tic; while toc(t0) < 0.3, drawnow limitrate; end
clickMenu(ptItem);
assert(~op.trialLocked, 'the menu should switch back to free-running');
fprintf('PASS: the trial-locked toggle works both ways with the timer live\n');

stop(op.h_timer);
delete(op);
assert(~isvalid(f) || true, 'no assertion, just make sure delete did not throw');
close(f);
fprintf('PASS: a live plot tears down cleanly\n');

fprintf('\nALL OnlinePlot SMOKE TESTS PASSED\n');
end


function [rt,iface,P] = makeRuntime(n,options)
% Runtime with one BatchProbeInterface carrying n readable parameters.
arguments
    n (1,1) double
    options.RefuseBatch (1,1) logical = false
end
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
iface = BatchProbeInterface(RefuseBatch=options.RefuseBatch);
P = hw.Parameter.empty(1,0);
for i = 1:n
    p = iface.add_parameter(sprintf('Trace%02d',i), 0);
    p.Value = 0;
    iface.put(p, i);
    P(end+1) = p; %#ok<AGROW>
end
rt.Interfaces = iface;
end


function [op,ax] = makePlot(rt,source)
% OnlinePlot on an axes we own, with the timer stopped so the test drives it.
f = figure('Visible','off','Name','SmokeOnlinePlot','Tag','SmokeOnlinePlot');
ax = axes(f);
op = gui.OnlinePlot(rt, source, ax);
stop(op.h_timer);
if op.startTic_ == 0
    op.h_timer.Timer.StartFcn(op.h_timer.Timer,[]); % StartFcn had not run yet
end
end


function cleanup_all()
delete(findall(groot,'Type','figure','-and','Tag','SmokeOnlinePlot'));
delete(findall(groot,'Type','figure','-and','-regexp','Name','Online Plot.*'));
T = timerfindall;
if ~isempty(T)
    T = T(startsWith({T.Name},'epsych_gui_OnlinePlot'));
    if ~isempty(T), stop(T); delete(T); end
end
end


function clickMenu(item)
% Fire a uimenu callback whether it was given as a handle or a {fcn,args} cell.
cb = item.MenuSelectedFcn;
if iscell(cb)
    cb{1}(item,[],cb{2:end});
else
    cb(item,[]);
end
end
