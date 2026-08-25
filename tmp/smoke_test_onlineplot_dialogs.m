function smoke_test_onlineplot_dialogs()
% smoke_test_onlineplot_dialogs()
% Drive gui.components.OnlinePlot's two modal operator dialogs and the
% gui.BehaviorGUI.addOnlinePlot helper.
%
% Kept apart from smoke_test_onlineplot_config so it can be run through
% `matlab -batch`: both dialogs block in uiwait, which corrupts the MATLAB
% MCP server's transport if the evaluation is interrupted.
%
% The claims under test:
%   - Reorder Traces... lists the traces TOP OF THE AXES FIRST, and its OK
%     applies the list reversed, so what the operator moved to the top of the
%     list ends up at the top of the plot
%   - cancelling either dialog changes nothing
%   - addOnlinePlot builds and registers a plot, and refuses a blank Source
%     instead of putting a list dialog in front of a starting session
%   - the registered plot reaches the component toolbar and has a glyph
%
% The dialogs are driven from a timer, which needs two things to be right:
% the driver must RETRY (under -batch the uifigure took ~2 s to become
% visible, and a one-shot driver that fires early leaves uiwait blocking
% forever), and it must never delete itself from inside its own callback.
%
%   matlab -batch "run('tmp/smoke_test_onlineplot_dialogs.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here);

TAG = 'SmokeOnlinePlotDlg';
cleanupObj = onCleanup(@() cleanup_all(TAG));
cleanup_all(TAG);

[rt,~,P] = makeRuntime(4);
f = figure('Visible','off','Name','SmokeOnlinePlotDlg','Tag',TAG);
ax = axes(f);
op = gui.components.OnlinePlot(rt,P,ax,1,PreferenceTag=TAG);
stop(op.h_timer);
if op.startTic_ == 0
    op.h_timer.Timer.StartFcn(op.h_timer.Timer,[]);
end

before = op.traceNames;
assert(isequal(before,{'Trace01','Trace02','Trace03','Trace04'}), ...
    'unexpected starting order: %s', strjoin(before,','));

action = [];   % what the driver should do when it finds a dialog

%% 1. Reorder dialog: cancel changes nothing -----------------------------
action = @closeReorder;
runDriven(@() op.reorderTraces());
assert(isequal(op.traceNames,before), 'cancelling the reorder dialog must change nothing');
fprintf('PASS: cancelling Reorder Traces... changes nothing\n');

%% 2. Reorder dialog: move the bottom trace to the top -------------------
% The list shows the axis top first, so Trace01 (bottom of the plot) is the
% LAST list entry. Three Move Ups puts it first in the list, i.e. at the top
% of the axes, which is last in traceNames.
action = @() driveReorder(3);
runDriven(@() op.reorderTraces());
assert(isequal(op.traceNames,{'Trace02','Trace03','Trace04','Trace01'}), ...
    'reorder dialog result wrong: %s', strjoin(op.traceNames,','));
assert(strcmp(op.hax.YAxis.TickLabels{end},'Trace01'), ...
    'the trace moved to the top of the list should label the top of the axis');
fprintf('PASS: Reorder Traces... maps list order to axis order, top first\n');

%% 3. Select Traces...: cancel changes nothing ---------------------------
now0 = op.traceNames;
action = @cancelListdlg;
runDriven(@() op.selectTraces());
assert(isequal(op.traceNames,now0), 'cancelling Select Traces... must change nothing');
fprintf('PASS: cancelling Select Traces... changes nothing\n');

delete(op); close(f);

%% 4. gui.BehaviorGUI.addOnlinePlot --------------------------------------
g = OnlinePlotBehaviorGUI(rt);
assert(~isempty(g.Plot) && isvalid(g.Plot), 'addOnlinePlot should have built a plot');
assert(isa(g.Plot,'gui.components.OnlinePlot'), 'and it should be a gui.components.OnlinePlot');
assert(isequal(g.Plot.traceNames,{'Trace01','Trace02'}), ...
    'the helper should honour Source, got %s', strjoin(g.Plot.traceNames,','));
assert(isequal(seconds(g.Plot.timeWindow),[-20 5]), ...
    'the helper should apply TimeWindow, got %s', mat2str(seconds(g.Plot.timeWindow)));
assert(isempty(g.Blank), 'a blank Source should return [] rather than open a dialog');
fprintf('PASS: addOnlinePlot builds, configures, and refuses a blank Source\n');

names = g.Toolbar.Names;
assert(any(names == "Online Plot"), ...
    'the registered plot should reach the component toolbar, got: %s', strjoin(names,', '));
fprintf('PASS: the plot reaches the component toolbar as a pop-out entry\n');

icon = gui.toolbarIcon("onlineplot");
assert(isequal(size(icon),[16 16 3]), 'gui.toolbarIcon should draw an onlineplot glyph');
fprintf('PASS: the class has a toolbar glyph of its own\n');

pl = g.Plot;
delete(g);
assert(~isvalid(pl), 'closing the GUI should tear the registered plot down');
fprintf('PASS: the registered plot is torn down with its GUI\n');

fprintf('\nALL OnlinePlot DIALOG SMOKE TESTS PASSED\n');


% --- nested: the driver and the call it drives --------------------------

    function runDriven(dialogCall)
        % Start the retry driver, make the blocking call, stop the driver.
        t = timer('Period',0.25,'ExecutionMode','fixedSpacing', ...
            'TasksToExecute',60,'BusyMode','drop');
        t.TimerFcn = @tick;
        start(t);
        dialogCall();
        if isvalid(t), stop(t); delete(t); end
    end

    function tick(src,~)
        try
            if action()
                stop(src);
            elseif src.TasksExecuted >= src.TasksToExecute - 1
                forceCloseModal(); % backstop, so uiwait cannot hang the run
            end
        catch ME
            fprintf(2,'dialog driver failed: %s\n',ME.message);
            forceCloseModal();
            stop(src);
        end
    end
end


function forceCloseModal()
f = [findall(groot,'Type','figure','Name','Reorder Traces'); ...
     findall(groot,'Type','figure','Name','Online Plot')];
for k = 1:numel(f)
    if isvalid(f(k)), uiresume(f(k)); delete(f(k)); end
end
end


function acted = closeReorder()
acted = false;
fig = readyReorderFig();
if isempty(fig), return; end
cb = fig.CloseRequestFcn;   % the same path as the window's X
cb(fig,[]);
acted = true;
end


function acted = driveReorder(nUp)
acted = false;
fig = readyReorderFig();
if isempty(fig), return; end
lb = findall(fig,'Type','uilistbox');
btn = findall(fig,'Type','uibutton');
up = btn(strcmp({btn.Text},'Move Up'));
okB = btn(strcmp({btn.Text},'OK'));
if isempty(lb) || isempty(up) || isempty(okB), return; end

lb(1).Value = lb(1).Items{end};      % the trace at the bottom of the plot
% The callback has to be pulled into a variable first: h.Prop(a,b) parses as
% INDEXING the property, not calling the handle it holds.
upFcn = up(1).ButtonPushedFcn;
okFcn = okB(1).ButtonPushedFcn;
for k = 1:nUp
    upFcn([],[]);
end
okFcn([],[]);
acted = true;
end


function fig = readyReorderFig()
% The visible, fully built Reorder Traces window, else empty. Visible goes on
% only after every widget exists and just before uiwait, so it is the signal
% that the dialog can be driven -- and a stale invisible one from an earlier
% test must never be picked up.
fig = [];
f = findall(groot,'Type','figure','Name','Reorder Traces');
f = f(arrayfun(@(h) isvalid(h) && strcmp(char(h.Visible),'on'), f));
if isempty(f), return; end
fig = f(1);
end


function acted = cancelListdlg()
% listdlg builds its figure invisible and positions it last, so a driver that
% acts on the first sight of the window races that positioning and errors
% inside listdlg. Wait for Visible AND for the widgets.
acted = false;
fig = findall(groot,'Type','figure','Name','Online Plot');
fig = fig(arrayfun(@(h) isvalid(h) && strcmp(char(h.Visible),'on'), fig));
if isempty(fig), return; end
if isempty(findall(fig(1),'Style','listbox')), return; end
% Closing the window, not pressing Cancel: listdlg is MATLAB's own dialog and
% invoking its Cancel callback out of band leaves its uiwait blocking. A
% closed window is the same answer from listdlg's side (ok = 0) and is what an
% operator dismissing it actually does.
delete(fig(1));
acted = true;
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


function cleanup_all(tag)
delete(findall(groot,'Type','figure','-and','-regexp','Tag','SmokeOnlinePlot.*'));
delete(findall(groot,'Type','figure','-and','Name','Reorder Traces'));
delete(findall(groot,'Type','figure','-and','-regexp','Name','Online Plot.*'));
T = timerfindall;
if ~isempty(T)
    T = T(startsWith({T.Name},'epsych_gui_OnlinePlot'));
    if ~isempty(T), stop(T); delete(T); end
end
G = 'epsych2_gui_OnlinePlot';
if ispref(G)
    p = fieldnames(getpref(G));
    p = p(startsWith(p,'Smoke') | startsWith(p,'OnlinePlotBehaviorGUI'));
    for k = 1:numel(p), rmpref(G,p{k}); end
end
if ispref(G,tag), rmpref(G,tag); end
if ispref('OnlinePlotBehaviorGUI'), rmpref('OnlinePlotBehaviorGUI'); end
end
