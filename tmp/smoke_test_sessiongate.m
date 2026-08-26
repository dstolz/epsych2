function smoke_test_sessiongate()
% smoke_test_sessiongate()
% Standing proof for gui.components.SessionGate and the component-exposure work that
% went in beside it:
%
%   1. gui.components.SessionGate on its own - release, wait, retire, and the
%      ModeChange catch-up that closes the gate a script never pressed.
%   2. The gui.BehaviorGUI add* helpers that had no entry point before
%      (history, scatter, psych plot, staircase plot, session clock, trial
%      timer, mode indicator, session gate), including the promise that a
%      helper needing something the session does not have returns [] rather
%      than taking the whole build down with it.
%   3. gui.components.Parameter_Control dependency gating (EnabledBy / DisabledBy /
%      setEnabled) and its composition with the interface-mode gate.
%   4. gui.components.Performance.TargetTrialType, which used to be hardcoded.
%   5. The gui.BehaviorBuilder palette entries added for components that
%      already existed but could not be placed.
%
%   matlab -batch "run('tmp/smoke_test_sessiongate.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF_TAG = 'smokeSessionGateTest';
outDir = fullfile(tempdir, 'epsych_sessiongate_smoke');
if ~exist(outDir,'dir'), mkdir(outDir); end
addpath(outDir);
cleanupObj = onCleanup(@() cleanupAll(PREF_TAG, outDir));

results = strings(0,2);

% 1. gui.components.SessionGate on its own -------------------------------------------
fig = uifigure('Visible','off','Position',[100 100 300 120]);
g = uigridlayout(fig,[1 1]);
gate = gui.components.SessionGate(g, Text='Start Now');

results(end+1,:) = check('The gate starts shut', ~gate.Released);
results(end+1,:) = check('It builds a live button', ...
    isvalid(gate.ButtonH) && strcmp(gate.ButtonH.Enable,'on'));
results(end+1,:) = check('The button carries the configured label', ...
    strcmp(gate.ButtonH.Text,'Start Now'));
results(end+1,:) = check('wait times out while it is shut', ~gate.wait(0.3));

% The GateOpened event fires exactly once, however many times release is
% called: a host arming a rig off it must not arm twice.
gateHits('reset');
lh = addlistener(gate,'GateOpened',@(~,~) gateHits('bump'));

gate.release();
results(end+1,:) = check('release opens the gate', gate.Released);
results(end+1,:) = check('wait returns at once once open', gate.wait(1));
results(end+1,:) = check('The button retired to a status line', ...
    strcmp(gate.ButtonH.Enable,'off') && strcmp(gate.ButtonH.Text,'Experiment Running'));
gate.release(); % second call must be inert
results(end+1,:) = check('GateOpened fires exactly once', gateHits('get') == 1);
delete(lh);

delete(fig);

% The ModeChange catch-up: a gate nobody pressed must not stand there armed
% over a session that is already running, and must say which kind it is.
[fig2, gate2, rt2] = makeGate();
rt2.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Preview));
results(end+1,:) = check('Preview opens the gate', gate2.Released);
results(end+1,:) = check('Preview is named on the retired button', ...
    strcmp(gate2.ButtonH.Text,'Preview Running'));
delete(fig2);

[fig3, gate3, rt3] = makeGate();
rt3.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Record));
results(end+1,:) = check('Record opens the gate', gate3.Released);
rt3.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Idle));
results(end+1,:) = check('A finished session reads Session Complete', ...
    strcmp(gate3.ButtonH.Text,'Session Complete'));
delete(fig3);

% An idle mode arriving BEFORE anything ran is a session waiting, not one
% that finished - the button must stay live.
[fig4, gate4, rt4] = makeGate();
rt4.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Idle));
results(end+1,:) = check('Idle before the start leaves the gate armed', ...
    ~gate4.Released && strcmp(gate4.ButtonH.Enable,'on'));
delete(fig4);

% 2. The add* helpers on a real BehaviorGUI --------------------------------
rt = makeRuntime();
gui1 = SessionGateSmokeGUI(rt);
results(end+1,:) = check('The GUI opens', isvalid(gui1) && isvalid(gui1.h_figure));
results(end+1,:) = check('addSessionGate built a gate', ...
    isa(gui1.hGate,'gui.components.SessionGate') && ~gui1.hGate.Released);
results(end+1,:) = check('addScatter built a scatter', ...
    isa(gui1.hScatter,'gui.components.ParameterScatter'));
results(end+1,:) = check('addSessionClock built a clock', ...
    isa(gui1.hClock,'gui.components.SessionClock'));
results(end+1,:) = check('addTrialTimer built a timer', ...
    isa(gui1.hTimer,'gui.components.ElapsedTrialTimer'));
results(end+1,:) = check('addModeIndicator built an indicator', ...
    isa(gui1.hMode,'gui.components.ModeIndicator'));

% The graceful half: this GUI has no psych object, so every psych-backed
% helper must hand back [] and leave the build standing.
results(end+1,:) = check('addHistory returns [] with no psych object', isempty(gui1.hHistory));
results(end+1,:) = check('addPsychPlot returns [] with no psych object', isempty(gui1.hPsychPlot));
results(end+1,:) = check('addStaircasePlot returns [] with no psych object', isempty(gui1.hStair));

results(end+1,:) = check('waitForSessionGate holds while the gate is shut', ...
    ~gui1.waitForSessionGate(0.3));
gui1.hGate.release();
results(end+1,:) = check('waitForSessionGate returns once released', ...
    gui1.waitForSessionGate(1));

f1 = gui1.h_figure;
delete(gui1);
results(end+1,:) = check('Teardown removes the window', ~isvalid(f1));
t = timerfindall;
if isempty(t)
    results(end+1,:) = check('No component timers survive teardown', true);
else
    results(end+1,:) = check('No component timers survive teardown', ...
        ~any(contains({t.Name},{'SessionClock','ElapsedTrialTimer'})));
end

% A GUI with no gate at all must not be held up by the wait.
rt2b = makeRuntime();
gui2 = NoGateSmokeGUI(rt2b);
results(end+1,:) = check('waitForSessionGate is a no-op with no gate', ...
    gui2.waitForSessionGate(0.2));
delete(gui2);

% 3. Parameter_Control dependency gating -----------------------------------
sw = hw.Software;
pEnable = sw.add_parameter('CatchEnabled', false, Type='Boolean');
pEnable.Value = false;
pRate = sw.add_parameter('CatchRate', 20);
pRate.Value = 20;
pOther = sw.add_parameter('OtherRate', 5);
pOther.Value = 5;
sw.connect();

fig5 = uifigure('Visible','off','Position',[100 100 420 240]);
g5 = uigridlayout(fig5,[3 1]);
cEnable = gui.components.Parameter_Control(g5, pEnable, Type='checkbox', autoCommit=true);
cRate   = gui.components.Parameter_Control(g5, pRate, EnabledBy=cEnable);
cOther  = gui.components.Parameter_Control(g5, pOther, DisabledBy=cEnable);

results(end+1,:) = check('EnabledBy greys a control whose governor is false', ...
    allOff(cRate));
results(end+1,:) = check('DisabledBy leaves it live while the governor is false', ...
    allOn(cOther));
results(end+1,:) = check('The label greys with its widgets', ...
    strcmp(cRate.h_label.Enable,'off'));

% Flip the governing PARAMETER rather than the widget: gating has to follow
% an external write (a phase load) as well as an operator click.
pEnable.Value = true;
results(end+1,:) = check('An external write ungates the dependent', allOn(cRate));
results(end+1,:) = check('...and gates the inverted one', allOff(cOther));

pEnable.Value = false;
results(end+1,:) = check('Flipping back re-gates', allOff(cRate) && allOn(cOther));

% setEnabled by hand, and the composition with the mode gate: a control the
% dependency gate has opened must still be dead while the rig is idle.
cRate.setEnabled(true);
results(end+1,:) = check('setEnabled opens the gate by hand', allOn(cRate));
sw.mode = hw.DeviceState.Idle;
results(end+1,:) = check('The mode gate closes it regardless', allOff(cRate));
cRate.setEnabled(true);
results(end+1,:) = check('...and setEnabled cannot reopen it over an idle rig', allOff(cRate));
sw.mode = hw.DeviceState.Record;
results(end+1,:) = check('Both gates open together', allOn(cRate));

% A dependent torn down before its governor must not break the next update.
delete(cOther);
ok = true;
try
    pEnable.Value = true;
catch
    ok = false;
end
results(end+1,:) = check('A deleted dependent is dropped, not thrown on', ok);

delete(fig5);
delete(sw);

% 4. gui.components.Performance.TargetTrialType ---------------------------------------
p = gui.components.Performance();
results(end+1,:) = check('Performance defaults to TrialType_0', ...
    p.TargetTrialType == epsych.BitMask.TrialType_0);
p.TargetTrialType = epsych.BitMask.TrialType_2;
results(end+1,:) = check('The target trial type is settable', ...
    p.TargetTrialType == epsych.BitMask.TrialType_2);
results(end+1,:) = check('The enum names the Count field', ...
    strcmp(string(p.TargetTrialType), "TrialType_2"));
delete(p.ContainerH);
delete(p);

% 5. Builder palette entries ------------------------------------------------
cat = gui.BehaviorBuilder.componentCatalog;
added = {'SessionGate','PhaseSelector','StatusBar','FilenameField', ...
         'SlidingWindow','OnlinePlot'};
results(end+1,:) = check('Every new type is in the catalog', ...
    all(ismember(added, {cat.Type})));

spec = buildPaletteSpec();
specFile = fullfile(outDir,'TmpGateBuilderGUI.eblt');
gui.BehaviorBuilder.saveSpecFile(spec, specFile);
loaded = gui.BehaviorBuilder.loadSpecFile(specFile);
results(end+1,:) = check('A spec holding them round-trips exactly', ...
    isequaln(gui.BehaviorBuilder.specValidate(spec), loaded));

mFile = gui.BehaviorBuilder.writeCode(loaded, specFile);
msgs = checkcode(mFile);
results(end+1,:) = check('The generated file is lint-clean', isempty(msgs));
src = fileread(mFile);
results(end+1,:) = check('The gate is emitted through add', ...
    contains(src,'gui.components.SessionGate'));
results(end+1,:) = check('The gate emits the waitForSessionGate handoff', ...
    contains(src,'waitForSessionGate'));
results(end+1,:) = check('The phase selector is emitted', contains(src,'gui.components.PhaseSelector('));
results(end+1,:) = check('The status bar is emitted', contains(src,'gui.components.StatusBar('));
results(end+1,:) = check('The filename field is emitted', contains(src,'gui.components.FilenameValidator('));
results(end+1,:) = check('The online plot is emitted with its source', ...
    contains(src,'gui.components.OnlinePlot(') && contains(src,'SmokeState'));

% An Online Plot with no source would send gui.components.OnlinePlot to a listdlg at
% construction, which a generated build must never do.
bad = loaded;
ix = strcmp({bad.Regions.Type},'OnlinePlot');
bad.Regions(ix).Options.Source = {};
results(end+1,:) = check('A sourceless Online Plot is refused', ...
    throwsWith(@() gui.BehaviorBuilder.specValidate(bad), 'epsych:BehaviorBuilder:BadRegion'));

badFn = loaded;
ix = strcmp({badFn.Regions.Type},'FilenameField');
badFn.Regions(ix).Options.DefaultFilename = 'notamatfile.txt';
results(end+1,:) = check('A non-.mat filename default is refused', ...
    throwsWith(@() gui.BehaviorBuilder.specValidate(badFn), 'epsych:BehaviorBuilder:BadRegion'));

rehash
clear('TmpGateBuilderGUI')
rtB = makeRuntime();
gb = TmpGateBuilderGUI(rtB);
results(end+1,:) = check('The generated GUI constructs', isvalid(gb) && isvalid(gb.h_figure));
gates = findall(gb.h_figure,'Type','uibutton');
results(end+1,:) = check('Its gate button is on screen', ...
    any(strcmp({gates.Text},'Begin Experiment')));
delete(gb);

% Report -------------------------------------------------------------------
report(results);
end


% =========================================================================
function [fig, gate, rt] = makeGate()
% A gate wired to a runtime, for the ModeChange cases.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
fig = uifigure('Visible','off','Position',[100 100 300 120]);
g = uigridlayout(fig,[1 1]);
gate = gui.components.SessionGate(g);
gate.attachRuntime(rt);
end


function rt = makeRuntime()
% Runtime with a connected software interface carrying test parameters.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

sw = hw.Software;
p = sw.add_parameter('SmokeFreq', 1000, Unit='Hz');
p.Value = 1000;
p = sw.add_parameter('SmokeLevel', 60);
p.Value = 60;
p = sw.add_parameter('SmokeState', 0);
p.Value = 0;
p.Access = 'Read';
rt.Interfaces = sw;
end


function spec = buildPaletteSpec()
% One region per newly placeable type, on a grid big enough to keep them
% apart. The psych-gated Sliding Window needs an analysis, and a Detection
% needs a parameter to group by.
spec = gui.BehaviorBuilder.specNew;
spec.ClassName  = 'TmpGateBuilderGUI';
spec.WindowName = 'Session Gate Builder Smoke';
spec.Psych.Type = 'Detection';
spec.Psych.Parameter = 'SmokeLevel';

sw = hw.Software;
sw.add_parameter('SmokeFreq', 1000, Unit='Hz');
sw.add_parameter('SmokeLevel', 60);
p = sw.add_parameter('SmokeState', 0);
p.Access = 'Read';
spec.ParameterSnapshot = gui.BehaviorBuilder.snapshotFromParameters( ...
    sw.all_parameters(includeTriggers=true));
delete(sw);

spec.Grid.Rows = 3;
spec.Grid.Cols = 2;
spec.Grid.RowHeight   = {'60','1x','1x'};
spec.Grid.ColumnWidth = {'1x','1x'};

spec.Regions = [ ...
    region('r1','SessionGate',   [1 1],[1 1]), ...
    region('r2','StatusBar',     [1 1],[2 2]), ...
    region('r3','PhaseSelector', [2 2],[1 1]), ...
    region('r4','FilenameField', [2 2],[2 2]), ...
    region('r5','SlidingWindow', [3 3],[1 1]), ...
    region('r6','OnlinePlot',    [3 3],[2 2])];

ix = strcmp({spec.Regions.Type},'OnlinePlot');
spec.Regions(ix).Options.Source = {'SmokeState'};
end


function r = region(id, type, rowSpan, colSpan)
r = struct('Id',id, 'Type',type, ...
    'Label',gui.BehaviorBuilder.catalogEntry(type).Display, ...
    'Row',rowSpan, 'Col',colSpan, 'PopOut',false, ...
    'Options',gui.BehaviorBuilder.defaultOptions(type));
end


function n = gateHits(action)
% Counter for the GateOpened event. An anonymous listener callback cannot
% assign to a caller's variable, so the count lives here.
persistent count
if isempty(count), count = 0; end
switch action
    case 'reset', count = 0;
    case 'bump',  count = count + 1;
end
n = count;
end


function tf = allOn(c)
tf = all(strcmp({c.widgets().Enable},'on'));
end

function tf = allOff(c)
tf = all(strcmp({c.widgets().Enable},'off'));
end


function tf = throwsWith(fcn, id)
tf = false;
try
    fcn();
catch ME
    tf = strcmp(ME.identifier, id);
end
end


function row = check(name, tf)
row = [string(name), string(logical(tf))];
end


function report(results)
pass = results(:,2) == "true";
for i = 1:size(results,1)
    if pass(i), tag = "  PASS"; else, tag = "**FAIL"; end
    fprintf('%s  %s\n', tag, results(i,1));
end
fprintf('\n%d passed, %d failed, %d total\n', sum(pass), sum(~pass), numel(pass));
assert(all(pass), 'smoke_test_sessiongate: %d check(s) failed', sum(~pass));
end


function cleanupAll(prefTag, outDir)
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
delete(findall(groot,'Type','figure','-and','Tag','smokeNoGateGUITest'));
delete(findall(groot,'Type','figure','-and','Tag','TmpGateBuilderGUI'));
if ispref(prefTag), rmpref(prefTag); end
if ispref('smokeNoGateGUITest'), rmpref('smokeNoGateGUITest'); end
if ispref('TmpGateBuilderGUI'), rmpref('TmpGateBuilderGUI'); end
rmpath(outDir);
end
