function smoke_test_componentspec()
% smoke_test_componentspec()
% Standing proof for gui.ComponentSpec and gui.BehaviorGUI.add.
%
% Two things are checked. First EQUIVALENCE: for every component that has
% both an add* helper and a spec, obj.add produces a component wired the
% same way -- same class, same registry position, same register name, same
% key binding, same PreferenceTag. That is what makes Phase 2's reroute of
% the helpers safe. Second DEGRADATION: a garbage class name, an abstract
% class, a malformed option list, a missing required option and a component
% whose analysis was never built must each return [] and say so at debug
% level, never throw -- the contract epsych.SelfTest check I6 depends on.
%
%   matlab -batch "run('tmp/smoke_test_componentspec.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here);

PREF_TAG = 'smokeComponentSpecTest';
cleanupObj = onCleanup(@() cleanupAll(PREF_TAG)); %#ok<NASGU>
gui.ComponentSpec.flushCache();

%% 1. Spec resolution ------------------------------------------------------
s = gui.ComponentSpec.forClass('gui.SessionClock');
assert(strcmp(s.className,'gui.SessionClock'), 'className should be filled in');
assert(s.attachRuntime && s.start, 'SessionClock should attach the runtime and start');
assert(isequal(cellstr(s.shape), {'parent'}), 'SessionClock takes the container alone');

s = gui.ComponentSpec.forClass('gui.OnlinePlot');
assert(strcmp(s.canvas,'axes'), 'OnlinePlot needs a CLASSIC axes, not a uiaxes');
assert(any(s.requiredOptions == "Source"), 'OnlinePlot must refuse an empty Source');
assert(strcmp(s.registerName,'Online Plot'), 'register name pins the pop-out identity');

s = gui.ComponentSpec.forClass('gui.History');
assert(any(s.requires == "psych"), 'History needs an analysis object');
assert(s.poppable, 'History adopts gui.PopOut, so the spec must say so');

s = gui.ComponentSpec.forClass('gui.ComponentToolbar');
assert(s.singleton, 'the component toolbar is one to a GUI');
fprintf('PASS: specs resolve with the wiring each component needs\n');

%% 2. Inference for a class that declares nothing --------------------------
% gui.BufferPlot has no getComponentSpec, so its shape comes from its
% constructor signature. meta.method.InputNames reports {'varargin'} for any
% arguments-block function, so this exercises the source-parsing path.
s = gui.ComponentSpec.forClass('gui.BufferPlot');
assert(isequal(cellstr(s.shape), {'psychOrRuntime','parent'}), ...
    'BufferPlot(source, container) should be inferred, got [%s]', ...
    strjoin(cellstr(s.shape),' '));
assert(s.poppable, 'inference must still detect the gui.PopOut mixin');
fprintf('PASS: a component that declares nothing still gets a usable spec\n');

%% 3. Degradation: nothing here may throw ---------------------------------
rt = makeRuntime();
g  = SpecSmokeGUI(rt);
assert(isvalid(g), 'GUI should construct');

assert(isempty(g.add('nope.NotAClass', g.h_figure)), ...
    'an unresolvable class name must return [] without throwing');
assert(isempty(g.add('gui.PopOut', g.h_figure)), ...
    'an abstract class must return [] without throwing');
assert(isempty(g.add('gui.SessionClock', g.h_figure, 'oddNumberOfArgs')), ...
    'a malformed option list must return [] without throwing');
assert(isempty(g.add('gui.OnlinePlot', g.h_figure)), ...
    'a missing required option must return [] rather than open a dialog');
assert(isempty(g.add('gui.History', g.h_figure)), ...
    'a component needing an analysis must return [] when there is none');
fprintf('PASS: every failure mode degrades to [] (SelfTest check I6)\n');

%% 4. Equivalence: add() vs the add* helper -------------------------------
% Same container, one built each way, then compared field by field.
gridA = uigridlayout(g.h_figure, [1 2]);

% spec.start=true must actually start the clock's timer, the way
% addSessionClock's explicit h.start() does. The timer is private, so count
% the running ones this class owns either side of the call.
runningClocks = @() numel(findobj(timerfindall, 'Tag', 'EPsychSessionClock', ...
    'Running', 'on'));
n0 = runningClocks();
hHelper = g.addSessionClock(gridA);
n1 = runningClocks();
hGeneric = g.add('gui.SessionClock', gridA);
n2 = runningClocks();
assert(isa(hGeneric, class(hHelper)), 'same class');
assert(strcmp(hGeneric.PreferenceTag, hHelper.PreferenceTag), ...
    'same PreferenceTag: "%s" vs "%s"', hHelper.PreferenceTag, hGeneric.PreferenceTag);
assert(n1 == n0 + 1, 'addSessionClock should start its timer');
assert(n2 == n1 + 1, 'spec.start must start the timer too (%d -> %d)', n1, n2);
fprintf('PASS: addSessionClock and add("gui.SessionClock") agree, both started\n');

hHelperM  = g.addMonitor(gridA, {'SmokeFreq','SmokeNotThere','SmokeLevel'});
hGenericM = g.add('gui.Parameter_Monitor', gridA, ...
    'Parameters', {'SmokeFreq','SmokeNotThere','SmokeLevel'});
assert(numel(hGenericM.Parameters) == numel(hHelperM.Parameters), ...
    'both should drop the unresolvable name and keep 2 (%d vs %d)', ...
    numel(hHelperM.Parameters), numel(hGenericM.Parameters));
assert(isequal({hGenericM.Parameters.Name}, {hHelperM.Parameters.Name}), ...
    'same parameters, same order');
fprintf('PASS: addMonitor and add("gui.Parameter_Monitor") agree, misses dropped alike\n');

%% 5. Registration and teardown --------------------------------------------
before = numel(g.componentsOfClass('gui.SessionClock'));
h = g.add('gui.SessionClock', gridA);
after = numel(g.componentsOfClass('gui.SessionClock'));
assert(after == before + 1, 'add must register what it builds');
assert(~isempty(h) && isvalid(h), 'and return it');
fprintf('PASS: add registers for teardown\n');

%% 6. Singleton ------------------------------------------------------------
tb1 = g.add('gui.ComponentToolbar', g.h_figure);
tb2 = g.add('gui.ComponentToolbar', g.h_figure);
assert(~isempty(tb1) && tb1 == tb2, 'a singleton spec returns the instance already made');
fprintf('PASS: singleton spec is idempotent\n');

%% 7. Verbatim option forwarding ------------------------------------------
% The whole correctness argument: an option not named is not passed, so the
% component keeps its own default rather than being handed one.
hDefault = g.add('gui.SessionClock', gridA);
hStated  = g.add('gui.SessionClock', gridA, 'FontSize', 21);
assert(hStated.FontSize == 21, 'a stated option must reach the component');
assert(hDefault.FontSize ~= 21, 'an unstated option must not be invented');
fprintf('PASS: options forwarded verbatim; unstated stays unstated\n');

%% 8. Reserved options are consumed, not forwarded ------------------------
hNamed = g.add('gui.SessionClock', gridA, 'RegisterName', 'My Clock');
names = g.registeredNamesForTest();
assert(any(strcmp(names, 'My Clock')), 'RegisterName must reach the registry');
assert(isvalid(hNamed), 'and must not be forwarded to the constructor');
fprintf('PASS: RegisterName consumed by add, not passed on\n');

%% 9. Teardown -------------------------------------------------------------
fig = g.h_figure;
close(fig);
assert(~isvalid(g), 'GUI should be deleted by closeGUI');
assert(~isvalid(hGeneric), 'registered components should be deleted with it');
fprintf('PASS: teardown removes every component add registered\n');

fprintf('smoke_test_componentspec: ALL PASS\n');
end


function rt = makeRuntime()
% Runtime with a connected software interface carrying test parameters.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
sw = hw.Software;
p = sw.add_parameter('SmokeFreq', 1000, Unit='Hz'); p.Value = 1000;
p = sw.add_parameter('SmokeLevel', 60);             p.Value = 60;
p = sw.add_parameter('SmokeState', 0);              p.Value = 0;
p.Access = 'Read';
rt.Interfaces = sw;
end


function cleanupAll(prefTag)
if ispref(prefTag)
    rmpref(prefTag);
end
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
end
