function smoke_test_behaviorgui()
% smoke_test_behaviorgui()
% Exercise gui.BehaviorGUI through the SmokeBehaviorGUI subclass: construction
% against a software runtime (controls, buttons, missing-name skipping,
% automatic Parameter_Update wiring), event dispatch (NewTrial/NewData/
% ModeChange hooks, once-only onFirstTrial, deferred closures, monitor
% stop on DeviceState.Stop), full teardown through the CloseRequestFcn
% path, the empty-runtime launch that SelfTest I6 performs, and
% single-instance replacement. Headless-safe: every GUI is closed before
% returning.
%
%   matlab -batch "run('tmp/smoke_test_behaviorgui.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % SmokeBehaviorGUI lives beside this test

PREF_TAG = 'smokeBehaviorGUITest';
cleanupObj = onCleanup(@() cleanupAll(PREF_TAG));

% 1. Construction against a software runtime ------------------------------
rt = makeRuntime();
g = SmokeBehaviorGUI(rt);
assert(isvalid(g), 'GUI object should be valid after construction');
assert(~isempty(g.h_figure) && isvalid(g.h_figure), 'main figure should exist');
assert(strcmp(g.h_figure.Tag, PREF_TAG), 'figure Tag should be the PreferenceTag');
assert(isvalid(g.hFreq) && isvalid(g.hLevel), 'named controls should be created');
assert(isempty(g.hMissing), 'unknown parameter name should return [] without error');
assert(isvalid(g.hPelletBtn) && isvalid(g.hToggleBtn), 'buttons should be created');
assert(strcmp(g.hPelletBtn.type,'momentary'), 'plain-named button should be momentary');
assert(strcmp(g.hToggleBtn.type,'toggle'), '~-prefixed button should be a toggle');
assert(isfield(g.hButtons,'SmokePellet') && isfield(g.hButtons,'x_SmokeToggle'), ...
    'buttons should be stored in hButtons by validName');
assert(isvalid(g.hMon), 'monitor should be created despite one missing name');
fprintf('PASS: construction, control creation, missing-name skipping\n');

% 2. Automatic Parameter_Update wiring ------------------------------------
wh = g.hUpdate.watchedHandles;
assert(numel(wh) == 2, 'update button should watch the 2 editable controls (got %d)', numel(wh));
assert(all(ismember({wh.Name}, {'SmokeFreq','SmokeLevel'})), ...
    'watchedHandles should be exactly the non-trigger, non-autoCommit controls');
fprintf('PASS: watchedHandles wired from the registry\n');

% 3. Event dispatch: hooks, once-only first trial, deferred closures ------
assert(~g.DeferredRan, 'deferred closure must not run before the first trial');
rt.EVENTS.notify('NewTrial');
rt.EVENTS.notify('NewTrial');
assert(g.NewTrialCount == 2, 'onNewTrial should run per NewTrial (got %d)', g.NewTrialCount);
assert(g.FirstTrialCount == 1, 'onFirstTrial should run exactly once (got %d)', g.FirstTrialCount);
assert(g.DeferredRan, 'deferred closure should run at the first NewTrial');
rt.EVENTS.notify('NewData');
assert(g.NewDataCount == 1, 'onNewData should have run once (got %d)', g.NewDataCount);
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Preview));
assert(g.ModeChangeCount == 1, 'onModeChange should have run once (got %d)', g.ModeChangeCount);
g.defer(@() g.markDeferred); % post-first-trial defer runs immediately
fprintf('PASS: event hooks, once-only onFirstTrial, deferred closures\n');

% 4. Monitor polling stops on DeviceState.Stop ----------------------------
assert(g.hMon.Timer.Running == "on", 'monitor timer should poll while running');
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Stop));
assert(g.hMon.Timer.Running == "off", 'monitor timer should stop on Stop mode');
assert(g.ModeChangeCount == 2, 'user hook should still run on Stop');
fprintf('PASS: monitor stops polling on Stop\n');

% 5. Teardown through the CloseRequestFcn path ----------------------------
fig = g.h_figure;
hFreq = g.hFreq; hUpdate = g.hUpdate; hMon = g.hMon; hBtn = g.hPelletBtn;
close(fig);
assert(~isvalid(g), 'GUI object should be deleted by closeGUI');
assert(~isvalid(fig), 'figure should be deleted');
assert(~isvalid(hFreq) && ~isvalid(hBtn), 'registered controls should be deleted');
assert(~isvalid(hUpdate), 'registered update button object should be deleted');
assert(~isvalid(hMon), 'registered monitor should be deleted');
t = timerfindall;
if ~isempty(t)
    assert(~any(startsWith({t.Name}, 'Parameter_Monitor_Timer')), ...
        'no monitor timers should survive teardown');
end
assert(ispref(PREF_TAG, 'FigurePosition'), 'figure position should persist on close');
fprintf('PASS: full teardown via CloseRequestFcn, position saved\n');

% 6. Empty-runtime launch (SelfTest I6 semantics) -------------------------
rtEmpty = epsych.Runtime;
rtEmpty.isTest = true;
rtEmpty.EVENTS = epsych.EventHub;
g2 = SmokeBehaviorGUI(rtEmpty);
assert(isvalid(g2) && isvalid(g2.h_figure), 'GUI must open against a runtime with no interfaces');
assert(isempty(g2.hFreq) && isempty(g2.hPelletBtn), ...
    'controls should be skipped when no parameters exist');
delete(g2);
assert(isempty(findall(groot,'Type','figure','-and','Tag',PREF_TAG)), ...
    'delete(obj) should also remove the figure');
fprintf('PASS: empty-runtime launch and programmatic delete\n');

% 7. Single-instance enforcement ------------------------------------------
g3 = SmokeBehaviorGUI(rt);
g4 = SmokeBehaviorGUI(rt);
assert(~isvalid(g3), 'first instance should be torn down by the second');
assert(isvalid(g4) && isvalid(g4.h_figure), 'second instance should be the survivor');
f = findall(groot,'Type','figure','-and','Tag',PREF_TAG);
assert(isscalar(f), 'exactly one figure should remain (got %d)', numel(f));
delete(g4);
fprintf('PASS: single-instance replacement\n');

% 8. ep_GenericGUI (refactored onto gui.BehaviorGUI) ---------------------------
% delete(obj) is used for teardown (not closeGUI) so the user's real
% 'ep_GenericGUI' position preference is never written by this test.
gg = ep_GenericGUI(rt);
assert(isvalid(gg) && isvalid(gg.h_figure), 'ep_GenericGUI should open');
assert(strcmp(gg.h_figure.Tag,'ep_GenericGUI'), 'Tag must remain ep_GenericGUI');
assert(isvalid(gg.h_logArea), 'event log area should exist');
assert(isfield(gg.hButtons,'SmokePellet') && isfield(gg.hButtons,'x_SmokeToggle'), ...
    'trigger-style parameters should become buttons');
assert(numel(gg.ParamControls) == 2 && all(cellfun(@isvalid, gg.ParamControls)), ...
    'writable parameters should become controls (got %d)', numel(gg.ParamControls));
assert(isvalid(gg.ParameterMonitor), 'read-only parameters should be monitored');
nLog = numel(gg.h_logArea.Value);
rt.EVENTS.notify('NewTrial');
rt.EVENTS.notify('NewData');
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Preview));
assert(numel(gg.h_logArea.Value) == nLog + 3, 'events should append to the log');
assert(endsWith(gg.h_logArea.Value{1}, 'Mode: Preview'), ...
    'ModeChange should log the new mode (got "%s")', gg.h_logArea.Value{1});
figG = gg.h_figure; monG = gg.ParameterMonitor;
delete(gg);
assert(~isvalid(figG) && ~isvalid(monG), 'ep_GenericGUI teardown should be complete');
fprintf('PASS: ep_GenericGUI on gui.BehaviorGUI\n');

% 9. Controls over parameters no trial has seeded yet ---------------------
% add_parameter fills Values, not Value, so a parameter stays empty until the
% first trial dispatch writes it. A behavior GUI built before that -- SelfTest I6,
% or a protocol whose parameter is absent from the trials table -- must still
% come up: the widget absorbs the empty, it does not abort the build.
swU = hw.Software;
swU.connect();
pBool  = swU.add_parameter('SmokeUnseededBool', false, Type='Boolean');
pFloat = swU.add_parameter('SmokeUnseededFloat', 10);
pFloat.Min = 5;
assert(isempty(pBool.Value) && isempty(pFloat.Value), ...
    'add_parameter should leave Value unseeded for this check');

figU = uifigure('Visible','off');
gl = uigridlayout(figU,[2 1]);
cBool  = gui.Parameter_Control(gl, pBool,  Type='checkbox');
cFloat = gui.Parameter_Control(gl, pFloat, Type='editfield');
assert(cBool.h_uiobj.Value == false, 'unseeded Boolean should render unchecked');
assert(cFloat.h_uiobj.Value == pFloat.Min, ...
    'unseeded numeric should land inside Limits (got %g, Min %g)', ...
    cFloat.h_uiobj.Value, pFloat.Min);
delete(cBool); delete(cFloat); delete(figU); delete(swU);
fprintf('PASS: controls over unseeded parameters\n');

% 10. The deprecated gui.BoxGUI shim --------------------------------------
% A lab's own GUI outside this repository still says "< gui.BoxGUI". It has
% to construct, inherit the base behavior, and reach the statics, since
% those are called as gui.BoxGUI.saveFigurePosition in code we do not own.
gL = LegacyShimGUI(rt);
assert(isa(gL,'gui.BehaviorGUI'), 'the shim must be a gui.BehaviorGUI');
assert(isvalid(gL.h_figure), 'a gui.BoxGUI subclass should still open');
assert(isequal(gui.BoxGUI.getSavedFigurePosition('noSuchTag',[1 2 3 4]), [1 2 3 4]), ...
    'statics should resolve through the deprecated name');
delete(gL);
fprintf('PASS: deprecated gui.BoxGUI subclass still constructs\n');

fprintf('smoke_test_behaviorgui: ALL PASS\n');
end


function rt = makeRuntime()
% Runtime with a connected software interface carrying test parameters.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

% add_parameter stores design-time Values; a live session populates Value
% during trial dispatch before the behavior GUI launches, so set Value here too.
sw = hw.Software;
p = sw.add_parameter('SmokePellet', 0, isTrigger=true);
p.Value = 0;
p = sw.add_parameter('~SmokeToggle', false, Type='Boolean');
p.Value = false;
p = sw.add_parameter('SmokeFreq', 1000, Unit='Hz');
p.Value = 1000;
p = sw.add_parameter('SmokeLevel', 60);
p.Value = 60;
p = sw.add_parameter('SmokeState', 0);
p.Value = 0;
p.Access = 'Read'; % monitor-only, not updatable
rt.Interfaces = sw;
end


function cleanupAll(prefTag)
% Remove test preferences and any stray test figures.
if ispref(prefTag)
    rmpref(prefTag);
end
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
end
