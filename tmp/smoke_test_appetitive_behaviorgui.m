function smoke_test_appetitive_behaviorgui()
% smoke_test_appetitive_behaviorgui()
% Exercise cl_AppetitiveDetection_BehaviorGUI (the gui.BehaviorGUI version of
% cl_AppetitiveDetection_GUI_B) against a software-only runtime:
% construction, control/button creation, Parameter_Update wiring, the
% NewTrial/NewData/ModeChange hooks, the hardware-free launch that
% SelfTest I6 performs, and full teardown. Headless-safe: every figure is
% closed and every preference this test writes is restored on exit.
%
%   matlab -batch "run('tmp/smoke_test_appetitive_behaviorgui.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF_TAG = 'cl_AppetitiveDetection_BehaviorGUI';
scatterPrefs = savedScatterPrefs();
nextTrialPrefs = savedNextTrialPrefs(PREF_TAG);
performancePrefs = savedComponentPrefs('epsych2_gui_SessionPerformance', PREF_TAG);
cleanupObj = onCleanup(@() cleanupAll(PREF_TAG, scatterPrefs, nextTrialPrefs, performancePrefs));

% The performance-panel assertions below expect the metrics build.m asks
% for, so a selection saved by a real session must not leak into the test.
clearComponentPrefs('epsych2_gui_SessionPerformance', PREF_TAG);

% 1. Construction ---------------------------------------------------------
rt = makeRuntime();
g = cl_AppetitiveDetection_BehaviorGUI(rt);
assert(isvalid(g) && isvalid(g.h_figure), 'GUI should be valid after construction');
assert(strcmp(g.h_figure.Tag, PREF_TAG), 'figure Tag should be the class name');
assert(isa(g.Psych,'psychophysics.Staircase'), 'createPsych should build a Staircase');
fprintf('PASS: construction\n');

% 2. Buttons --------------------------------------------------------------
% '~TrialDelivery' exercises the trigger-prefix tolerance: the button is
% keyed by validName, so the prefixed parameter lands in x_TrialDelivery.
expectBtn = {'DropPellet','Shape','ReminderTrials','ManualTrigger','x_TrialDelivery','SpoofTrough'};
for b = expectBtn
    assert(isfield(g.hButtons,b{1}), 'missing button "%s"', b{1});
end
assert(strcmp(g.hButtons.DropPellet.type,'momentary'), 'Pellet should be momentary');
assert(strcmp(g.hButtons.x_TrialDelivery.type,'toggle'), 'Deliver Trials should be a toggle');
assert(isvalid(g.hReminder), 'reminder toggle should be cached for onNewData');
assert(isequal(g.P.Shape.PostUpdateFcn, @cl_AppetitiveDetection_BehaviorGUI.trigger_Shape), ...
    'Shape parameter should carry the trigger_Shape hook');
fprintf('PASS: control buttons and parameter hooks\n');

% 3. Panels and components ------------------------------------------------
assert(isvalid(g.ParameterMonitor), 'trial state monitor should exist');
assert(numel(g.ParameterMonitor.Parameters) == 11, ...
    'monitor should track 11 parameters (got %d)', numel(g.ParameterMonitor.Parameters));
assert(any(strcmp({g.ParameterMonitor.Parameters.Name},'P_Catch_Current')), ...
    'monitor should include the live catch probability');
assert(isvalid(g.h_ScatterPanel), 'parameter scatter should exist');
assert(isvalid(g.ResponseHistory), 'response history should exist');
assert(isvalid(g.NextTrialPanel) && isvalid(g.NextTrialPanel.TableH), 'next trial panel should exist');
assert(isvalid(g.Performance) && isa(g.Performance.Analysis,'psychophysics.SessionMetrics'), ...
    'session performance panel should exist and compute through SessionMetrics');
assert(isequal(g.Performance.Metrics, ["HitRate","FARate","AbortRate","DPrime"]), ...
    'performance panel should show the paradigm''s four metrics');
assert(isvalid(g.PhaseSelector), 'phase selector should exist');
assert(isvalid(g.SessionClock), 'session clock should exist');
assert(isequal(g.SessionClock.PanelH.Layout.Row, 1) && isequal(g.SessionClock.PanelH.Layout.Column, 5), ...
    'session clock should sit in the open top-row cell (row 1, column 5)');
assert(isvalid(g.NotesButton) && g.NotesButton.IsButtonOnly, ...
    'notes button should exist in its button-only form');
assert(g.NotesButton.Store == rt.NOTES, 'notes button should write to the session store');
assert(numel(g.NotesButton.OpenH.Parent.ColumnWidth) == 8, ...
    'the button row should hold six triggers, Notes, and Regenerate');
assert(isvalid(g.RegenerateButton), 'regenerate button should exist');
assert(isequal(g.RegenerateButton.ButtonH.Parent, g.NotesButton.OpenH.Parent), ...
    'regenerate button should sit in the same row, in the last column');
fprintf('PASS: panels and components\n');

% 4. Automatic Parameter_Update wiring ------------------------------------
% Everything on the staircase and stimulus-delay rows commits on edit, so
% what is left for the deferred-commit button is the plain trial and sound
% controls. Depth is not among them: both bound-property rows (Min and Max)
% are autoCommit.
wh = g.UpdateButton.watchedHandles;
watched = sort(string({wh.Name}));
expectWatched = sort(["ITIDur","RespWinPreStim","RespWinPostStim","NumPellets","TimeoutDur","dBSPL"]);
assert(isequal(watched, expectWatched), ...
    'watchedHandles should be exactly the deferred-commit controls (got %s)', ...
    strjoin(watched, ', '));
fprintf('PASS: watchedHandles wired from the registry\n');

% 5. Catch-trial switch ---------------------------------------------------
% The p(Catch) fields all carry the autoCommit tag of the parameter they
% edit, so one regexp findobj collects the Min/Max range row (tagged _Min
% and _Max) together with the Step field. Driving the parameter (rather than
% the widget) is the phase-load path, and it must move the checkbox and the
% enable state together.
hCatchEnable = findobj(g.h_figure,'Tag','ACPC_CatchTrialsEnabled');
hPCatch      = findobj(g.h_figure,'-regexp','Tag','^ACPC_P_Catch(_M(in|ax))?$');
assert(isscalar(hCatchEnable), 'catch-trial checkbox should exist');
assert(numel(hPCatch) == 3, 'expected 3 p(Catch) fields (got %d)', numel(hPCatch));
assert(all(pcatchEnableStates(hPCatch) == "on"), 'p(Catch) fields should start enabled');

g.P.CatchTrialsEnabled.Value = false;
assert(~hCatchEnable.Value, 'clearing the parameter should clear the checkbox');
assert(all(pcatchEnableStates(hPCatch) == "off"), ...
    'clearing the switch should disable the p(Catch) fields');

g.P.CatchTrialsEnabled.Value = true;
assert(all(pcatchEnableStates(hPCatch) == "on"), ...
    'restoring the switch should re-enable the p(Catch) fields');
fprintf('PASS: catch-trial checkbox gates the p(Catch) fields\n');

% 5b. Stimulus-delay randomization gates the Min/Max row -------------------
% Both entries of the Type='range' row must follow the randomization
% checkbox together; disabling only the left one would leave an editable Max
% that the fixed-delay mode ignores.
hDelayRand = findobj(g.h_figure,'Type','uicheckbox','-and','Tag','ACPC_StimDelay');
hDelayLo   = findobj(g.h_figure,'Tag','ACPC_StimDelay_Min');
hDelayHi   = findobj(g.h_figure,'Tag','ACPC_StimDelay_Max');
assert(isscalar(hDelayRand),'randomization checkbox should exist');
assert(isscalar(hDelayLo) && isscalar(hDelayHi), ...
    'stimulus delay bounds should be one range row of two fields');
assert(isequal(hDelayLo.Parent,hDelayHi.Parent),'both bound entries share a row');
assert(all(pcatchEnableStates([hDelayLo hDelayHi]) == "off"), ...
    'bounds start disabled while the delay is fixed');

g.P.StimDelay.isRandom = true;
assert(hDelayRand.Value,'setting the parameter should tick the checkbox');
assert(all(pcatchEnableStates([hDelayLo hDelayHi]) == "on"), ...
    'randomizing should enable both bound entries');

g.P.StimDelay.isRandom = false;
assert(all(pcatchEnableStates([hDelayLo hDelayHi]) == "off"), ...
    'returning to a fixed delay should disable both bound entries');
fprintf('PASS: randomization checkbox gates both stimulus-delay bounds\n');

% 5c. Stimulus-delay training mode ----------------------------------------
% Training mode used to be a bare uibutton('state'), so its state lived only
% in the widget and no phase could record it. It is now a checkbox over a
% parameter build() creates when the protocol does not declare one. Driving
% the PARAMETER (not the widget) is the phase-load path, which must open and
% close the training window and suspend/restore StimDelay randomization.
pTrain = rt.find_parameter('StimDelayTrainingEnabled', silenceParameterNotFound=true);
assert(isscalar(pTrain), 'build should create StimDelayTrainingEnabled');
assert(pTrain.PersistWithPhase, 'training mode must travel with a saved phase');
assert(~pTrain.UpdateEveryTrial, 'training mode is operator state, not dispatched');
assert(~hw.Parameter.isTransientControl(pTrain), ...
    'a PersistWithPhase toggle must not read as a momentary control');

hTrain = findobj(g.h_figure,'Type','uicheckbox','-and','Tag','ACPC_StimDelayTrainingEnabled');
assert(isscalar(hTrain), 'training-mode checkbox should exist');
assert(~hTrain.Value, 'training mode should start off');

% A disable with no preceding enable (a phase writing false into a fresh
% session) must be a no-op, not an attempt to restore a snapshot that was
% never taken.
pTrain.Value = false;
assert(isempty(g.StaircaseTrainingGUIs) || ~g.StaircaseTrainingGUIs.isKey('StimDelay'), ...
    'switching training off while already off must not open anything');

g.P.StimDelay.isRandom = true;   % the state training must suspend and restore
pTrain.Value = true;
assert(hTrain.Value, 'setting the parameter should tick the checkbox');
assert(g.StaircaseTrainingGUIs.isKey('StimDelay'), 'training mode should open its window');
assert(~g.P.StimDelay.isRandom, 'training mode suspends stimulus-delay randomization');

% Re-asserting an already-on toggle must not re-snapshot: doing so would
% capture the suspended isRandom=false and lose the value to restore.
pTrain.Value = true;
assert(g.P.StimDelay.UserData.STAIRCASE.isRandom, ...
    'a repeated enable must not overwrite the staircase snapshot');

pTrain.Value = false;
assert(~hTrain.Value, 'clearing the parameter should clear the checkbox');
assert(~g.StaircaseTrainingGUIs.isKey('StimDelay'), 'training mode should close its window');
assert(g.P.StimDelay.isRandom, 'switching training off restores randomization');
g.P.StimDelay.isRandom = false;
fprintf('PASS: training-mode checkbox is a phase-persistent parameter\n');

% 6. NewTrial hook --------------------------------------------------------
rt.EVENTS.notify('NewTrial', epsych.TrialsData(fakeTrials(1)));
assert(isequal(g.NextTrialPanel.TableH.Data, {'Depth','0.5';'TrialTypeNames','STIM'}), ...
    'next trial panel should show the stimulus trial');
rt.EVENTS.notify('NewTrial', epsych.TrialsData(fakeTrials(2)));
assert(isequal(g.NextTrialPanel.TableH.Data, {'Depth','0';'TrialTypeNames','CATCH'}), ...
    'next trial panel should show the catch trial');
fprintf('PASS: gui.NextTrial updates from the NewTrial event\n');

% 7. NewData hook ---------------------------------------------------------
% The Reminder request must SURVIVE a completed trial. NewData is broadcast
% before the runtime asks the selector for the next trial, so a GUI that
% cleared the toggle here withdrew the request in the very pass that was
% about to honor it and no reminder was ever presented. The selector
% consumes the request itself, in the pass that grants it.
pReminder = g.hReminder.Parameter;
pReminder.Value = 1;   % safe to run trigger_ReminderTrial: it only logs
g.Psych.Events.notify('NewData');
assert(pReminder.Value == 1, 'a completed trial must not clear the Reminder toggle');
pReminder.Value = 0;
fprintf('PASS: onNewData leaves the Reminder request standing\n');

% 8. ModeChange: monitor polling stops on Stop, resumes on Record ---------
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Stop));
assert(g.ParameterMonitor.Timer.Running == "off", 'monitor should stop on Stop');
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Record));
assert(g.ParameterMonitor.Timer.Running == "on", 'monitor should resume on Record');
fprintf('PASS: onModeChange starts/stops the trial state monitor\n');

% 9. Teardown through the CloseRequestFcn path ---------------------------
% gui.Helper.timed_color_change leaves a 1 s one-shot timer that writes
% back into the control it flashed; let those drain before tearing down so
% the test output is not polluted by their (pre-existing) stale-handle
% error.
pause(1.2);

fig = g.h_figure;
mon = g.ParameterMonitor; scat = g.h_ScatterPanel; hist = g.ResponseHistory;
nextTrial = g.NextTrialPanel;
perf = g.Performance; perfAnalysis = perf.Analysis;
psych = g.Psych;
close(fig);
assert(~isvalid(g) && ~isvalid(fig), 'closeGUI should delete the object and figure');
assert(~isvalid(mon) && ~isvalid(scat) && ~isvalid(hist) && ~isvalid(nextTrial) && ~isvalid(perf), ...
    'registered components should be deleted');
assert(~isvalid(perfAnalysis), 'the performance panel should delete the SessionMetrics it created');
assert(~isvalid(psych), 'psych object should be deleted');
t = timerfindall;
if ~isempty(t)
    assert(~any(startsWith({t.Name}, 'Parameter_Monitor_Timer')), ...
        'no monitor timers should survive teardown');
end
fprintf('PASS: teardown\n');

% 10. Hardware-free launch (SelfTest I6 semantics) ------------------------
rtEmpty = epsych.Runtime;
rtEmpty.isTest = true;
rtEmpty.EVENTS = epsych.EventHub;
g2 = cl_AppetitiveDetection_BehaviorGUI(rtEmpty);
assert(isvalid(g2) && isvalid(g2.h_figure), 'GUI must open against a runtime with no interfaces');
assert(isempty(g2.Psych), 'no Depth parameter means no staircase');
assert(isempty(fieldnames(g2.hButtons)), 'no parameters means no buttons');
delete(g2);
assert(isempty(findall(groot,'Type','figure','-and','Tag',PREF_TAG)), ...
    'delete(obj) should also remove the figure');
fprintf('PASS: hardware-free launch\n');

% 11. Single-instance enforcement ----------------------------------------
gA = cl_AppetitiveDetection_BehaviorGUI(rt);
gB = cl_AppetitiveDetection_BehaviorGUI(rt);
assert(~isvalid(gA), 'first instance should be replaced by the second');
assert(isscalar(findall(groot,'Type','figure','-and','Tag',PREF_TAG)), ...
    'exactly one figure should remain');
pause(1.2);
delete(gB);
fprintf('PASS: single-instance replacement\n');

% 12. Block-randomized stimulus delay ------------------------------------
% A protocol that declares StimDelayList gets a different set of delay
% controls: the checkbox drives StimDelayBlockEnabled instead of
% StimDelay.isRandom (which randi would use to overwrite the sequence's
% value), and the Min/Max row describes the list rather than StimDelay's own
% bounds.
rtBlock = makeBlockRuntime();
gC = cl_AppetitiveDetection_BehaviorGUI(rtBlock);

pStep = rtBlock.find_parameter('StimDelayStep', silenceParameterNotFound=true);
assert(isscalar(pStep), 'build should create StimDelayStep when the protocol has none');
assertNear(pStep.Value, 250, 'the step should seed from StimDelayList''s own value');
assert(~pStep.UpdateEveryTrial && pStep.PersistWithPhase, ...
    'the step is operator state: not dispatched, but carried by a phase');
% The whole reason it is a separate parameter: 250 is below StimDelayList.Min,
% so neither hw.Parameter nor the edit field could hold it there.
hStep = findobj(gC.h_figure,'Tag','ACPC_StimDelayStep');
assert(isscalar(hStep) && hStep.Limits(1) <= 250, ...
    'the step field must accept a step finer than the list Min');

pBlock = rtBlock.find_parameter('StimDelayBlockEnabled', silenceParameterNotFound=true);
assert(isscalar(pBlock), 'build should create StimDelayBlockEnabled');
assert(pBlock.PersistWithPhase, 'the randomization switch must travel with a phase');
assert(pBlock.Value, 'a 13-value list should default the switch on');

hBlock = findobj(gC.h_figure,'Type','uicheckbox','-and','Tag','ACPC_StimDelayBlockEnabled');
assert(isscalar(hBlock) && hBlock.Value, 'the checkbox should exist and start ticked');
assert(isempty(findobj(gC.h_figure,'Type','uicheckbox','-and','Tag','ACPC_StimDelay')), ...
    'with a list present the checkbox must not be bound to StimDelay.isRandom');

hLo  = findobj(gC.h_figure,'Tag','ACPC_StimDelayList_Min');
hHi  = findobj(gC.h_figure,'Tag','ACPC_StimDelayList_Max');
hJit = findobj(gC.h_figure,'Tag','ACPC_StimDelayJitter');
assert(isscalar(hLo) && isscalar(hHi) && isscalar(hJit), ...
    'the list bounds and the jitter should each have a control');
assert(all(pcatchEnableStates([hLo hHi hStep hJit]) == "on"), ...
    'the list controls should be enabled while randomization is on');

pBlock.Value = false;
assert(all(pcatchEnableStates([hLo hHi hStep hJit]) == "off"), ...
    'switching randomization off should grey the whole list description');
pBlock.Value = true;

% Training mode owns StimDelay outright, so it greys the randomization
% controls too -- and hands them back in the state the checkbox says.
pTrainB = rtBlock.find_parameter('StimDelayTrainingEnabled', silenceParameterNotFound=true);
pTrainB.Value = true;
assert(all(pcatchEnableStates([hBlock hLo hHi hStep hJit]) == "off"), ...
    'training mode should grey the randomization controls');
pTrainB.Value = false;
assert(all(pcatchEnableStates([hBlock hLo hHi hStep hJit]) == "on"), ...
    'leaving training mode should restore them');
fprintf('PASS: block-randomized delay controls replace the isRandom pair\n');

pause(1.2);
delete(gC);

fprintf('smoke_test_appetitive_behaviorgui: ALL PASS\n');
end


function assertNear(actual, expected, varargin)
msg = sprintf(varargin{:});
assert(numel(actual) == numel(expected) && all(abs(actual(:)-expected(:)) < 1e-9), ...
    '%s (expected %s, got %s)', msg, mat2str(expected,6), mat2str(actual,6));
end


function rt = makeBlockRuntime()
% Runtime whose protocol describes a block-randomized stimulus delay:
% StimDelayList carries the ends of the list, and the step is left for build
% to create -- which is the case an existing protocol is in.
rt = makeRuntime();
sw = rt.Interfaces(1);

p = sw.add_parameter('StimDelayList', 250, Type='Float');
p.Min = 1000;
p.Max = 4000;

p = sw.add_parameter('StimDelayJitter', 10, Type='Float');
p.Min = 0;
p.Max = 250;
p.Value = 10;
end


function rt = makeRuntime()
% Runtime with a software interface carrying the parameters the GUI expects.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

sw = hw.Software;

addp(sw,'DropPellet',0,isTrigger=true);
addp(sw,'SpoofTrough',0,isTrigger=true);
addBool(sw,'Shape',false);
addBool(sw,'ReminderTrials',false);
addBool(sw,'ManualTrigger',false);
addBool(sw,'~TrialDelivery',false);

p = addp(sw,'Depth',0.5,Unit='%'); p.Min = 0; p.Max = 1;
addp(sw,'Depth_StepOnMiss',0.05);
addp(sw,'Depth_StepOnHit',0.05);
p = addp(sw,'P_Catch',0.1); p.Min = 0; p.Max = 1;
% Catch-trial on/off switch. cl_AppetitiveStimDetect creates this at run
% start; declare it here so the checkbox it feeds is exercised.
p = addBool(sw,'CatchTrialsEnabled',true); p.UpdateEveryTrial = false;
addp(sw,'ITIDur',5000,Unit='ms');
addp(sw,'RespWinPreStim',100,Unit='ms');
addp(sw,'RespWinPostStim',500,Unit='ms');
addBool(sw,'RepeatDelayOnAbort',false);
p = addp(sw,'StimDelay',1000,Unit='ms'); p.Min = 500; p.Max = 2000;
addp(sw,'StimDelayTrain_StepUp',350);
addp(sw,'StimDelayTrain_StepDown',100);
p = sw.add_parameter('NumPellets',[1 2 3]); p.Value = 1;
addp(sw,'TimeoutDur',8000,Unit='ms');
addp(sw,'dBSPL',60,Unit='dB SPL');
addp(sw,'TrialType',0);

% read-only monitor parameters
addBool(sw,'Platform',false,'Read');
addBool(sw,'Trough',false,'Read');
addBool(sw,'InTrial',false,'Read');
addBool(sw,'DelayPeriod',false,'Read');
addBool(sw,'RespWindow',false,'Read');
p = addp(sw,'PelletTotal',0);  p.Access = 'Read';
p = addp(sw,'RespWinDelay',0); p.Access = 'Read';
p = addp(sw,'RespLatency',0);  p.Access = 'Read';
p = addp(sw,'RespCode',0);     p.Access = 'Read';

% Live catch probability. cl_AppetitiveStimDetect creates this at run start;
% declare it here so the monitor row it feeds is exercised.
p = addp(sw,'P_Catch_Current',0,Format='%0.2f'); p.UpdateEveryTrial = false;

rt.Interfaces = sw;
end


function p = addp(sw,name,value,varargin)
% add_parameter stores design-time Values; a live session assigns Value
% during trial dispatch, so set it here too.
p = sw.add_parameter(name,value,varargin{:});
p.Value = value;
end


function p = addBool(sw,name,value,access)
p = sw.add_parameter(name,value,Type='Boolean');
p.Value = logical(value);
if nargin > 3, p.Access = access; end
end


function s = pcatchEnableStates(h)
% Enable states of the p(Catch) widgets as strings, so the assertions read
% the same whether Enable comes back as char or OnOffSwitchState.
s = arrayfun(@(x) string(x.Enable), h);
end


function T = fakeTrials(trialID)
% Minimal stand-in for RUNTIME.TRIALS as consumed by gui.NextTrial.
T.Subject = 'TEST';
T.BoxID = 1;
T.NextTrialID = trialID;
T.trials = {0.5, 'STIM'; 0, 'CATCH'};   % Depth, TrialTypeNames
T.writeparams = {'Depth','TrialTypeNames'};
T.writeParamIdx.Depth = 1;
T.writeParamIdx.TrialTypeNames = 2;
end


function s = savedScatterPrefs()
% The scatter panel shares its preference key with the original GUI_B;
% snapshot it so this test leaves the user's saved selections untouched.
s = [];
if ispref('epsych2_gui_ParameterScatter','AppetitiveDetection_ScatterPlot')
    s = getpref('epsych2_gui_ParameterScatter','AppetitiveDetection_ScatterPlot');
end
end


function s = savedNextTrialPrefs(prefTag)
% gui.NextTrial keys its saved selection to the hosting figure Tag, which
% here is the same as PREF_TAG; snapshot it so this test leaves the user's
% saved selection untouched.
s = [];
validName = matlab.lang.makeValidName(prefTag);
if ispref('epsych2_gui_NextTrial',validName)
    s = getpref('epsych2_gui_NextTrial',validName);
end
end


function s = savedComponentPrefs(group, prefTag)
% Snapshot a component preference keyed to the hosting figure Tag, so this
% test leaves the user's saved settings untouched.
s = [];
validName = matlab.lang.makeValidName(prefTag);
if ispref(group,validName)
    s = getpref(group,validName);
end
end


function clearComponentPrefs(group, prefTag)
validName = matlab.lang.makeValidName(prefTag);
if ispref(group,validName)
    rmpref(group,validName);
end
end


function restoreComponentPrefs(group, prefTag, saved)
validName = matlab.lang.makeValidName(prefTag);
if isempty(saved)
    clearComponentPrefs(group, prefTag);
else
    setpref(group,validName,saved);
end
end


function cleanupAll(prefTag, scatterPrefs, nextTrialPrefs, performancePrefs)
if ispref(prefTag)
    rmpref(prefTag);
end
if isempty(scatterPrefs)
    if ispref('epsych2_gui_ParameterScatter','AppetitiveDetection_ScatterPlot')
        rmpref('epsych2_gui_ParameterScatter','AppetitiveDetection_ScatterPlot');
    end
else
    setpref('epsych2_gui_ParameterScatter','AppetitiveDetection_ScatterPlot',scatterPrefs);
end
validName = matlab.lang.makeValidName(prefTag);
if isempty(nextTrialPrefs)
    if ispref('epsych2_gui_NextTrial',validName)
        rmpref('epsych2_gui_NextTrial',validName);
    end
else
    setpref('epsych2_gui_NextTrial',validName,nextTrialPrefs);
end
restoreComponentPrefs('epsych2_gui_SessionPerformance', prefTag, performancePrefs);
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
end
