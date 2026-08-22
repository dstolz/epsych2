function smoke_test_onlineplot_config()
% smoke_test_onlineplot_config()
% Exercise gui.OnlinePlot's configurability: pop-out, programmatic and
% operator-facing trace selection, y-axis reordering, aesthetics, and
% cross-session persistence.
%
% The claims under test:
%   - setWatched replaces the traces, relabels the axis and resizes the ring
%   - setWatched narrows a bitmask bank to named bits and can widen it back
%   - setTraceOrder permutes by index or by name, and CARRIES per-trace
%     colours and widths with their traces
%   - a saved order naming traces that have gone, or missing ones that are
%     there, reorders what it can and leaves the rest alone
%   - the aesthetics menu items reach the same properties a script sets, and
%     a scalar line width restyles EVERY trace rather than only the first
%   - every operator change is written to preferences and restored by the
%     next plot built under the same key
%   - a saved SELECTION is honoured when the operator made it and ignored
%     when the constructor was given an explicit source
%   - popOut opens a second, independent plot with its own preference key,
%     its own timer and its own traces; closing it leaves the host alone
%
% Headless-safe: preferences are written under a private tag and removed,
% every figure closed and every timer deleted before returning.
%
%   matlab -batch "run('tmp/smoke_test_onlineplot_config.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % BatchProbeInterface

PREF_GROUP = 'epsych2_gui_OnlinePlot';
TAG = 'SmokeOnlinePlotCfg';

cleanupObj = onCleanup(@() cleanup_all(PREF_GROUP,TAG));
cleanup_all(PREF_GROUP,TAG); % start from a clean slate

%% 1. setWatched: programmatic trace replacement -------------------------
[rt,iface,P] = makeRuntime(6);
[op,ax] = makePlot(rt,P(1:3),TAG);

assert(isequal(op.traceNames,{'Trace01','Trace02','Trace03'}), ...
    'traceNames should report the source order, got %s', strjoin(op.traceNames,','));

op.setWatched(P([5 4]));
assert(isequal(op.traceNames,{'Trace05','Trace04'}), ...
    'setWatched should replace the traces in the given order, got %s', strjoin(op.traceNames,','));
assert(op.N == 2 && numel(op.lineH) == 2, 'the axes should be rebuilt to 2 traces');
assert(size(op.Buffers,1) == 2, 'the ring should be resized to 2 rows');
assert(isequal(cellstr(op.hax.YAxis.TickLabels(:))',{'Trace05','Trace04'}), ...
    'the y tick labels should follow the new traces');
iface.reset_counts(); op.update();
assert(iface.GetCalls == 1, 'the read plan should have been rebuilt, not re-used');
fprintf('PASS: setWatched replaces traces, labels and buffers\n');

%% 2. setTraceOrder: index and name forms, styles follow -----------------
op.setWatched(P(1:4));
op.lineColors = [1 0 0; 0 1 0; 0 0 1; 1 1 0];
op.lineWidth  = [4;6;8;10];

op.setTraceOrder([3 1 4 2]);
assert(isequal(op.traceNames,{'Trace03','Trace01','Trace04','Trace02'}), ...
    'index reorder wrong: %s', strjoin(op.traceNames,','));
assert(isequal(op.lineColors(1,:),[0 0 1]), 'the colour should have moved with Trace03');
assert(op.lineWidth(1) == 8, 'the width should have moved with Trace03');
assert(isequal(op.lineH(1).Color,[0 0 1]), 'the redrawn line should carry the moved colour');
fprintf('PASS: setTraceOrder permutes by index and carries per-trace style\n');

op.setTraceOrder({'Trace02','Trace04','Trace01','Trace03'});
assert(isequal(op.traceNames,{'Trace02','Trace04','Trace01','Trace03'}), ...
    'name reorder wrong: %s', strjoin(op.traceNames,','));
assert(isequal(op.lineColors(1,:),[0 1 0]), 'Trace02 should still be green');
fprintf('PASS: setTraceOrder permutes by name\n');

% a partial / stale order: unknown names ignored, unnamed traces keep their
% relative place at the end
op.setTraceOrder({'Trace04','NotAParameter','Trace01'});
assert(isequal(op.traceNames,{'Trace04','Trace01','Trace02','Trace03'}), ...
    'partial reorder wrong: %s', strjoin(op.traceNames,','));
fprintf('PASS: a partial or stale order degrades instead of throwing\n');

n0 = op.traceNames;
op.setTraceOrder([1 2 3]);   % wrong length: refused, nothing changes
assert(isequal(op.traceNames,n0), 'a bad permutation must be refused');
fprintf('PASS: a bad permutation is refused\n');

%% 3. Aesthetics, programmatic and through the menu ----------------------
cm = op.hax.ContextMenu;
assert(~isempty(cm) && isvalid(cm), 'the plot should carry a context menu');

lwItem = findMenu(cm,'aes|lineWidth|14');
clickMenu(lwItem);
assert(numel(op.lineWidth) == op.N && all(op.lineWidth == 14), ...
    'a scalar line width must restyle EVERY trace, got %s', mat2str(op.lineWidth'));
assert(all(arrayfun(@(h) h.LineWidth == 14, op.lineH)), ...
    'the change should reach the live lines without a rebuild');
fprintf('PASS: the line-width menu restyles every trace\n');

palItem = findMenu(cm,'aes|palette|Grayscale');
clickMenu(palItem);
assert(strcmp(op.palette,'Grayscale'), 'the palette menu should set the palette');
c = op.lineColors;
assert(all(abs(c(:,1)-c(:,2)) < 1e-9 & abs(c(:,2)-c(:,3)) < 1e-9), ...
    'a greyscale palette should give neutral colours');
assert(isequal(palItem.Checked,matlab.lang.OnOffSwitchState('on')), ...
    'the chosen palette should be ticked');
fprintf('PASS: the palette menu re-colours and ticks itself\n');

gridItem = findMenu(cm,'tgl|showGrid');
clickMenu(gridItem);
assert(~op.showGrid, 'the grid toggle should turn the grid off');
assert(strcmp(char(op.hax.XGrid),'off'), 'and it should reach the axes');
clickMenu(gridItem);
assert(op.showGrid && strcmp(char(op.hax.XGrid),'on'), 'and back on again');
fprintf('PASS: toggles reach the axes and round-trip\n');

op.setWatched(P(1:3));
op.lineColors = [1 0 0; 0 1 0; 0 0 1];
resetItem = findMenu(cm,'uic_resetStyle');
clickMenu(resetItem);
assert(strcmp(op.palette,'Okabe-Ito') && op.showGrid && op.setZeroToNan, ...
    'Reset Appearance should restore the shipped look');
assert(isequal(op.traceNames,{'Trace01','Trace02','Trace03'}), ...
    'Reset Appearance must not disturb the trace selection');
fprintf('PASS: Reset Appearance restores styling and leaves the traces alone\n');

% the per-trace colour menu names exactly the current traces
tcMenu = findMenu(cm,'uic_traceColors');
assert(isequal({tcMenu.Children.Text}, fliplr(op.traceNames)), ...
    'the trace-colour menu should list the current traces');
fprintf('PASS: the per-trace colour menu tracks the trace list\n');

%% 4. Preferences persist across a rebuild -------------------------------
op.setTraceOrder({'Trace03','Trace01','Trace02'});
clickMenu(findMenu(cm,'aes|palette|Turbo')); % first: a palette change resets per-trace colours
op.setTraceColor(1,[0.1 0.2 0.3]);
op.setTraceColor(2,[0.4 0.5 0.6]);
op.setTraceColor('Trace02',[0.7 0.8 0.9]); % by name; it is trace 3 after the reorder
op.timeWindow = seconds([-30 4]);
op.trialMarker = false;
op.saveConfiguration();

wantNames = op.traceNames;
wantColors = op.lineColors;
delete(op); close(ancestor(ax,'figure'));

[op2,ax2] = makePlot(rt,P(1:3),TAG);
assert(isequal(op2.traceNames,wantNames), ...
    'the saved order should come back: wanted %s, got %s', ...
    strjoin(wantNames,','), strjoin(op2.traceNames,','));
assert(max(abs(op2.lineColors(:)-wantColors(:))) < 1e-9, ...
    'the saved per-trace colours should come back');
assert(strcmp(op2.palette,'Turbo'), 'the saved palette should come back');
assert(isequal(seconds(op2.timeWindow),[-30 4]), ...
    'the saved time window should come back, got %s', mat2str(seconds(op2.timeWindow)));
assert(~op2.trialMarker, 'the saved trial-marker setting should come back');
fprintf('PASS: order, colours, palette and window survive a rebuild\n');

% a colour is keyed by NAME, so it survives being handed a different order
op2.setTraceOrder({'Trace01','Trace02','Trace03'});
i3 = find(strcmp(op2.traceNames,'Trace03'));
assert(max(abs(op2.lineColors(i3,:) - wantColors(1,:))) < 1e-9, ...
    'a per-trace colour should stay with its trace across a reorder');
fprintf('PASS: per-trace styling is keyed by trace name, not position\n');

delete(op2); close(ancestor(ax2,'figure'));

%% 5. A saved selection defers to an explicit source ---------------------
% Written as though the operator had picked two traces by hand.
s = getpref(PREF_GROUP,TAG);
s.TraceOrder = {'Trace05','Trace06'};
s.SelectionByOperator = true;
s.TraceStyle = struct('Name',{'Trace05','Trace06'},'Color',{[1 0 0],[0 1 0]},'Width',{6,6});
setpref(PREF_GROUP,TAG,s);

[op3,ax3] = makePlot(rt,P(1:3),TAG);
assert(isequal(op3.traceNames,{'Trace05','Trace06'}), ...
    'an operator-chosen selection should be restored, got %s', strjoin(op3.traceNames,','));
fprintf('PASS: an operator-chosen selection is restored over the constructor source\n');
delete(op3); close(ancestor(ax3,'figure'));

s.SelectionByOperator = false;
setpref(PREF_GROUP,TAG,s);
[op4,ax4] = makePlot(rt,P(1:3),TAG);
assert(isequal(op4.traceNames,{'Trace01','Trace02','Trace03'}), ...
    'a selection the operator did not make must not override build(), got %s', ...
    strjoin(op4.traceNames,','));
fprintf('PASS: a non-operator selection defers to the constructor source\n');
delete(op4); close(ancestor(ax4,'figure'));

%% 6. Bitmask mode: bit selection and reorder ----------------------------
rtb = epsych.Runtime; rtb.isTest = true; rtb.EVENTS = epsych.EventHub;
bm = BatchProbeInterface();
pBank = bm.add_parameter('~BMid-Behavior', 0);
bits = {'Lick','Spout','Reward','Timeout'};
for i = 1:numel(bits)
    bm.add_parameter(sprintf('~BM-Behavior#%d^%s', i-1, bits{i}), 0);
end
rtb.Interfaces = bm;
bm.put(pBank, 15); % all four bits set

[opb,axb] = makePlot(rtb,'Behavior','SmokeOnlinePlotBM');
assert(isequal(opb.traceNames,bits), 'all four bits should plot');

opb.setWatched({'Reward','Lick'});
assert(isequal(opb.traceNames,{'Reward','Lick'}), ...
    'setWatched should narrow the bank to the named bits, got %s', strjoin(opb.traceNames,','));
bm.reset_counts(); opb.update();
assert(bm.GetCalls == 1, 'a narrowed bank is still one read, got %d', bm.GetCalls);
col = opb.Buffers(:, opb.BufferIdx - 1);
assert(all(col == 1), 'both selected bits are set in mask 15, got %s', mat2str(col(:)'));
fprintf('PASS: a bitmask bank narrows to named bits and still costs one read\n');

opb.setWatched(bits); % widen back
assert(isequal(opb.traceNames,bits), 'a hidden bit should come back');
fprintf('PASS: hidden bits can be brought back\n');

opb.setTraceOrder({'Timeout','Lick','Reward','Spout'});
assert(isequal(opb.traceNames,{'Timeout','Lick','Reward','Spout'}), ...
    'bitmask reorder wrong: %s', strjoin(opb.traceNames,','));
bm.reset_counts(); opb.update();
assert(bm.GetCalls <= 4, 'a reordered bank must not multiply reads, got %d', bm.GetCalls);
col = opb.Buffers(:, opb.BufferIdx - 1);
assert(all(col == 1), 'every bit of mask 15 should still read 1 after a reorder');
bm.put(pBank, 4); % only bit 2 (Reward)
opb.update();
col = opb.Buffers(:, opb.BufferIdx - 1);
assert(isnan(col(1)) && isnan(col(2)) && col(3) == 1 && isnan(col(4)), ...
    'after the reorder, bit decoding should follow the traces, got %s', mat2str(col(:)'));
fprintf('PASS: reordering a bank keeps each trace bound to its own bit\n');

delete(opb); close(ancestor(axb,'figure'));

%% 7. Pop-out ------------------------------------------------------------
[op5,ax5] = makePlot(rt,P(1:3),TAG);
assert(isa(op5,'gui.PopOut'), 'gui.OnlinePlot should be a gui.PopOut adopter');
assert(~op5.hasPopOut(), 'nothing should be open yet');
poItem = findall(op5.hax.ContextMenu,'Tag',gui.PopOut.POPOUT_MENU_TAG);
assert(~isempty(poItem), 'the context menu should carry the pop-out item');

h = op5.popOut();
assert(~isempty(h) && isvalid(h) && op5.hasPopOut(), 'popOut should open a second plot');
assert(h ~= op5, 'the pop-out is a separate instance');
assert(isequal(h.traceNames,op5.traceNames), 'it should open showing what the host shows');
assert(~isequal(h.h_timer.Timer, op5.h_timer.Timer), 'it should have a timer of its own');
assert(isvalid(op5.lineH(1)), 'the host must be left untouched');
fprintf('PASS: popOut opens an independent second plot\n');

h.setWatched(P(4:6));
assert(isequal(op5.traceNames,{'Trace01','Trace02','Trace03'}), ...
    'changing the pop-out must not disturb the host');
assert(isequal(h.traceNames,{'Trace04','Trace05','Trace06'}), 'the pop-out should have changed');
fprintf('PASS: the pop-out has its own trace selection\n');

again = op5.popOut();
assert(again == h, 'popOut again should raise the same window, not open a second');

hFig = op5.PopOutFigure;
op5.closePopOut();
assert(~op5.hasPopOut() && ~isvalid(hFig), 'closePopOut should close the window');
assert(isvalid(op5) && isvalid(op5.lineH(1)), 'the host survives its pop-out closing');
fprintf('PASS: the pop-out raises rather than duplicating, and closes cleanly\n');

% and closing the host takes an open pop-out with it
h2 = op5.popOut();
f2 = op5.PopOutFigure;
delete(op5);
assert(~isvalid(h2) && ~isvalid(f2), 'deleting the host should take its pop-out window');
fprintf('PASS: deleting the host closes its pop-out\n');
close(ancestor(ax5,'figure'));

fprintf('\nALL OnlinePlot CONFIG SMOKE TESTS PASSED\n');
end


function [rt,iface,P] = makeRuntime(n)
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
iface = BatchProbeInterface();
P = hw.Parameter.empty(1,0);
for i = 1:n
    p = iface.add_parameter(sprintf('Trace%02d',i), 0);
    p.Value = 0;
    iface.put(p, 1);
    P(end+1) = p; %#ok<AGROW>
end
rt.Interfaces = iface;
end


function [op,ax] = makePlot(rt,source,tag)
f = figure('Visible','off','Name','SmokeOnlinePlotCfg','Tag',tag);
ax = axes(f);
op = gui.OnlinePlot(rt, source, ax, 1, PreferenceTag=tag);
stop(op.h_timer);
if op.startTic_ == 0
    op.h_timer.Timer.StartFcn(op.h_timer.Timer,[]);
end
end


function m = findMenu(cm,tag)
m = findall(cm,'Tag',tag);
assert(~isempty(m),'no menu item tagged "%s"',tag);
m = m(1);
end


function clickMenu(item)
cb = item.MenuSelectedFcn;
if iscell(cb)
    cb{1}(item,[],cb{2:end});
else
    cb(item,[]);
end
end


function cleanup_all(prefGroup,tag)
delete(findall(groot,'Type','figure','-and','-regexp','Tag','SmokeOnlinePlot.*'));
delete(findall(groot,'Type','figure','-and','-regexp','Name','Online Plot.*'));
T = timerfindall;
if ~isempty(T)
    T = T(startsWith({T.Name},'epsych_gui_OnlinePlot'));
    if ~isempty(T), stop(T); delete(T); end
end
if ispref(prefGroup)
    p = fieldnames(getpref(prefGroup));
    p = p(startsWith(p,'Smoke'));
    for k = 1:numel(p)
        rmpref(prefGroup,p{k});
    end
end
if ispref(prefGroup,tag), rmpref(prefGroup,tag); end
end
