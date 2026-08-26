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
s = gui.ComponentSpec.forClass('gui.components.SessionClock');
assert(strcmp(s.className,'gui.components.SessionClock'), 'className should be filled in');
assert(s.attachRuntime && s.start, 'SessionClock should attach the runtime and start');
assert(isequal(cellstr(s.shape), {'parent'}), 'SessionClock takes the container alone');

s = gui.ComponentSpec.forClass('gui.components.OnlinePlot');
assert(strcmp(s.canvas,'axes'), 'OnlinePlot needs a CLASSIC axes, not a uiaxes');
assert(any(s.requiredOptions == "Source"), 'OnlinePlot must refuse an empty Source');
assert(strcmp(s.registerName,'Online Plot'), 'register name pins the pop-out identity');

s = gui.ComponentSpec.forClass('gui.components.History');
assert(any(s.requires == "psych"), 'History needs an analysis object');
assert(s.poppable, 'History adopts gui.PopOut, so the spec must say so');

s = gui.ComponentSpec.forClass('gui.components.ComponentToolbar');
assert(s.singleton, 'the component toolbar is one to a GUI');
fprintf('PASS: specs resolve with the wiring each component needs\n');

% Regression: every component in the package must at least LOAD. gui.Triggers
% inherited the Sealed gui.Helper, so metaclass resolution threw and the class
% could not be constructed at all -- invisible for as long as nothing tried.
%
% The comparison has to be against what is ON DISK. meta.package.ClassList
% silently OMITS a class it cannot load, so enumerating the package and
% checking those names could never fail: it would just describe a shorter
% list. That omission is exactly how the bug stayed hidden.
pkgDir = fullfile(fileparts(which('gui.ComponentSpec')), '+components');
onDisk = [ ...
    string(erase({dir(fullfile(pkgDir,'@*')).name}, '@')), ...
    string(erase({dir(fullfile(pkgDir,'*.m')).name}, '.m'))];
onDisk = onDisk(strlength(onDisk) > 0);
unloadable = strings(1,0);
for nm = onDisk
    full = "gui.components." + nm;
    ok_ = false;
    try
        ok_ = ~isempty(meta.class.fromName(full)) || ~isempty(which(char(full)));
    catch
    end
    if ~ok_, unloadable(end+1) = full; end %#ok<SAGROW>
end
assert(isempty(unloadable), ...
    'these components are on disk but cannot be loaded at all: %s', ...
    strjoin(cellstr(unloadable), ', '));
assert(~isempty(meta.class.fromName('gui.components.Triggers')), ...
    'gui.components.Triggers must not inherit the Sealed gui.Helper');
fprintf('PASS: all %d classes in gui.components load\n', numel(onDisk));

%% 2. Inference for a class that declares nothing --------------------------
% gui.components.MicrophonePlot has no getComponentSpec, so its shape comes from its
% constructor signature. meta.method.InputNames reports {'varargin'} for any
% arguments-block function, so this exercises the source-parsing path that
% inference actually depends on.
s = gui.ComponentSpec.forClass('gui.components.MicrophonePlot');
assert(isequal(cellstr(s.shape), {'arg:Parameter','parent'}), ...
    'MicrophonePlot(Parameter, Parent) should be inferred, got [%s]', ...
    strjoin(cellstr(s.shape),' '));

% And the mixin is detected by walking meta.class.SuperclassList, not by
% superclasses(), which omits Hidden ancestors.
assert(gui.ComponentSpec.forClass('gui.ParameterTracker').poppable == false, ...
    'a plain handle class is not poppable');
assert(gui.ComponentSpec.forClass('gui.components.BufferPlot').poppable, ...
    'a gui.PopOut adopter must be detected as poppable');
fprintf('PASS: a component that declares nothing still gets a usable spec\n');

%% 3. Degradation: nothing here may throw ---------------------------------
rt = makeRuntime();
g  = SpecSmokeGUI(rt);
assert(isvalid(g), 'GUI should construct');

assert(isempty(g.add('nope.NotAClass', g.h_figure)), ...
    'an unresolvable class name must return [] without throwing');
assert(isempty(g.add('gui.PopOut', g.h_figure)), ...
    'an abstract class must return [] without throwing');
assert(isempty(g.add('gui.components.SessionClock', g.h_figure, 'oddNumberOfArgs')), ...
    'a malformed option list must return [] without throwing');
assert(isempty(g.add('gui.components.OnlinePlot', g.h_figure)), ...
    'a missing required option must return [] rather than open a dialog');

% Parameter lists arrive in every shape a caller already holds. Resolution
% runs BEFORE the try/catch around construction, so each of these used to
% escape add as a thrown error from cellstr. A cell of handles is the
% normal case for a build that resolved them itself, not a mistake.
gridD = uigridlayout(g.h_figure, [1 1]);
hM = g.add('gui.components.Parameter_Monitor', gridD, 'Parameters', {g.P.SmokeFreq, g.P.SmokeLevel});
assert(~isempty(hM) && numel(hM.Parameters) == 2, 'a cell of hw.Parameter handles must be accepted');
hM = g.add('gui.components.Parameter_Monitor', gridD, 'Parameters', {'SmokeFreq', g.P.SmokeLevel});
assert(~isempty(hM) && numel(hM.Parameters) == 2, 'a mix of names and handles must be accepted');
hM = g.add('gui.components.Parameter_Monitor', gridD, 'Parameters', ["SmokeFreq" "SmokeLevel"]);
assert(~isempty(hM) && numel(hM.Parameters) == 2, 'a string array must be accepted');
hM = g.add('gui.components.Parameter_Monitor', gridD, 'Parameters', 42);
assert(~isempty(hM) && isempty(hM.Parameters), ...
    'a numeric list is dropped at debug level, not thrown');

% A class that is not on the path yet must resolve once it appears. forClass
% memoizes, and a memoized MISS would stay unresolvable for the session --
% which is what a GUI built before a lab folder is added, or SelfTest run
% before startup finished, would hit.
lateDir = fullfile(tempdir, 'epsych_componentspec_late');
if ~isfolder(lateDir), mkdir(lateDir); end
lateFile = fullfile(lateDir, 'SpecLateArrival.m');
lateCleanup = onCleanup(@() cleanupLate(lateDir, lateFile)); %#ok<NASGU>
gui.ComponentSpec.flushCache();
assert(isempty(gui.ComponentSpec.forClass('SpecLateArrival').className), ...
    'the late class should be unknown before it exists');
fid = fopen(lateFile, 'w');
fprintf(fid, ['classdef SpecLateArrival < handle\n  methods\n' ...
    '    function obj = SpecLateArrival(parent, options)\n' ...
    '      arguments\n        parent\n        options.X = 1\n      end\n' ...
    '    end\n  end\nend\n']);
fclose(fid);
addpath(lateDir); rehash path;
assert(strcmp(gui.ComponentSpec.forClass('SpecLateArrival').className, 'SpecLateArrival'), ...
    'a class that appears after a miss must resolve without a cache flush');
assert(isempty(g.add('gui.components.History', g.h_figure)), ...
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
hHelper = g.add('gui.components.SessionClock', gridA);
n1 = runningClocks();
hGeneric = g.add('gui.components.SessionClock', gridA);
n2 = runningClocks();
assert(isa(hGeneric, class(hHelper)), 'same class');
assert(strcmp(hGeneric.PreferenceTag, hHelper.PreferenceTag), ...
    'same PreferenceTag: "%s" vs "%s"', hHelper.PreferenceTag, hGeneric.PreferenceTag);
assert(n1 == n0 + 1, 'addSessionClock should start its timer');
assert(n2 == n1 + 1, 'spec.start must start the timer too (%d -> %d)', n1, n2);
fprintf('PASS: addSessionClock and add("gui.components.SessionClock") agree, both started\n');

hHelperM  = g.add('gui.components.Parameter_Monitor', gridA, 'Parameters', {'SmokeFreq','SmokeNotThere','SmokeLevel'});
hGenericM = g.add('gui.components.Parameter_Monitor', gridA, ...
    'Parameters', {'SmokeFreq','SmokeNotThere','SmokeLevel'});
assert(numel(hGenericM.Parameters) == numel(hHelperM.Parameters), ...
    'both should drop the unresolvable name and keep 2 (%d vs %d)', ...
    numel(hHelperM.Parameters), numel(hGenericM.Parameters));
assert(isequal({hGenericM.Parameters.Name}, {hHelperM.Parameters.Name}), ...
    'same parameters, same order');
fprintf('PASS: addMonitor and add("gui.components.Parameter_Monitor") agree, misses dropped alike\n');

%% 5. Registration and teardown --------------------------------------------
before = numel(g.componentsOfClass('gui.components.SessionClock'));
h = g.add('gui.components.SessionClock', gridA);
after = numel(g.componentsOfClass('gui.components.SessionClock'));
assert(after == before + 1, 'add must register what it builds');
assert(~isempty(h) && isvalid(h), 'and return it');
fprintf('PASS: add registers for teardown\n');

%% 6. Singleton ------------------------------------------------------------
tb1 = g.add('gui.components.ComponentToolbar', g.h_figure);
tb2 = g.add('gui.components.ComponentToolbar', g.h_figure);
assert(~isempty(tb1) && tb1 == tb2, 'a singleton spec returns the instance already made');
fprintf('PASS: singleton spec is idempotent\n');

%% 7. Verbatim option forwarding ------------------------------------------
% The whole correctness argument: an option not named is not passed, so the
% component keeps its own default rather than being handed one.
hDefault = g.add('gui.components.SessionClock', gridA);
hStated  = g.add('gui.components.SessionClock', gridA, 'FontSize', 21);
assert(hStated.FontSize == 21, 'a stated option must reach the component');
assert(hDefault.FontSize ~= 21, 'an unstated option must not be invented');
fprintf('PASS: options forwarded verbatim; unstated stays unstated\n');

% Regression: EnabledBy through addControl. gui.Parameter_Control has always
% taken this option and two doc pages have always shown it, but the old
% addControl declared its own arguments block and silently dropped anything
% not listed there -- so the documented call errored. Verbatim forwarding is
% what fixes it, which is why the proof belongs here.
colG  = g.controlColumn(uigridlayout(g.h_figure, [1 1]), Title = 'Gating');
hGov  = g.addControl(colG, 'SmokeGate');
hGate = g.addControl(colG, 'SmokeGated', EnabledBy = hGov);
assert(~isempty(hGate), 'addControl(..., EnabledBy=...) must build a control');
assert(strcmp(hGate.widgets().Enable, 'off'), ...
    'the dependent should be greyed while its governor is false');
g.P.SmokeGate.Value = true;
drawnow
assert(strcmp(hGate.widgets().Enable, 'on'), ...
    'and live once the governor turns true');
fprintf('PASS: addControl forwards EnabledBy, as both doc pages promise\n');

%% 8. Reserved options are consumed, not forwarded ------------------------
hNamed = g.add('gui.components.SessionClock', gridA, 'RegisterName', 'My Clock');
names = g.registeredNamesForTest();
assert(any(strcmp(names, 'My Clock')), 'RegisterName must reach the registry');
assert(isvalid(hNamed), 'and must not be forwarded to the constructor');
fprintf('PASS: RegisterName consumed by add, not passed on\n');

%% 9. The point of the whole mechanism ------------------------------------
% A component that lives outside gui.components, declares no spec, and is
% registered nowhere. If this works, adding a component needs no edit to
% gui.BehaviorGUI, to gui.BehaviorBuilder, or to any table.
s = gui.ComponentSpec.forClass('SmokeOutsideComponent');
assert(isequal(cellstr(s.shape), {'runtime','parent'}), ...
    'the constructor signature alone should say RUNTIME first, container second (got [%s])', ...
    strjoin(cellstr(s.shape),' '));

hOut = g.add('SmokeOutsideComponent', gridA, 'Color', 'red');
assert(~isempty(hOut) && isvalid(hOut), 'an unregistered outside component must build');
assert(strcmp(hOut.Color,'red'), 'its options must be forwarded');
assert(isequal(hOut.RUNTIME, g.RUNTIME), 'and it must have been handed the runtime');
assert(~isempty(g.componentsOfClass('SmokeOutsideComponent')), ...
    'and it must be registered for teardown like anything else');
fprintf('PASS: a component from outside the toolbox works with no registration\n');

%% 10. Review findings, pinned ---------------------------------------------
% Option names match case-insensitively, as the arguments block they land in
% would match them. Every consumer in add tests exact field names, so before
% canonicalizeOptions_ a caller's 'autocommit=false' sat beside the Button
% variant's fixedOptions 'autoCommit=true' and LOST to it -- the opposite of
% "the caller always wins".
hB = g.addButton(gridA, 'SmokeFreq', autocommit = false);
assert(~isempty(hB) && ~hB.autoCommit, 'a lower-case option must still outrank fixedOptions');
hC = g.addControl(gridA, 'SmokeLevel', text = 'Level!');
assert(strcmp(hC.Text, 'Level!'), 'a lower-case Text must reach the control, not be overwritten');
hV = g.add('gui.components.Parameter_Control', gridA, 'Parameter', 'SmokeFreq', 'variant', 'Button');
assert(~isempty(hV) && hV.autoCommit, 'a lower-case reserved name (variant) must be honoured');
fprintf('PASS: option names are matched case-insensitively against the spec\n');

% The inference regex is anchored to a line that starts with "function".
% SpecRegexProbe's header comment and an earlier method both carry
% "= SpecRegexProbe(...)" decoys; unanchored, [^=]* reached them first.
s = gui.ComponentSpec.forClass('SpecRegexProbe');
assert(isequal(cellstr(s.shape), {'parent','arg:channel'}), ...
    'the regex must find the real constructor, not a usage example (got [%s])', ...
    strjoin(cellstr(s.shape),' '));
hP = g.add('SpecRegexProbe', gridA, 'Color', 'red');
assert(~isempty(hP) && hP.Channel == 1, ...
    'an unstated trailing positional is dropped so the constructor default applies');
fprintf('PASS: constructor inference ignores usage examples in comments\n');

% A required positional the constructor has no default for is refused as a
% CONDITION (debug level, []), not reported as a defective constructor.
assert(isempty(g.add('gui.components.FilenameValidator', gridA)), ...
    'FilenameValidator without defaultFilename must return []');
assert(~isempty(g.add('gui.components.FilenameValidator', gridA, 'defaultFilename', 'x.mat')), ...
    'and build once it is stated');
fprintf('PASS: a missing required positional is a condition, not a defect\n');

% toPromptField must speak promptFieldsImpl_'s vocabulary, or the builder's
% generic Configure dialog renders every option as a text field.
k1 = gui.ComponentSpecOption('name','a','inputType','logical').toPromptField().Kind;
k2 = gui.ComponentSpecOption('name','b','inputType','choice','choices',{{'x','y'}}).toPromptField().Kind;
assert(strcmp(k1,'logical') && strcmp(k2,'choice'), ...
    'toPromptField Kinds must be logical/choice, got %s/%s', k1, k2);
fprintf('PASS: spec options map onto the shared form''s field kinds\n');

% Builder side. A fully-qualified class name is a valid region Type all the
% way through -- specValidate used to look the Type up in the catalog
% directly and refuse what catalogEntry advertised -- and a class placed
% twice is handed a unique PreferenceTag ONLY when its spec declares that
% option. ModeIndicator declares none; SessionClock does.
bs = gui.BehaviorBuilder.specNew;
bs.ClassName = 'TmpSpecReviewGUI';
mk = @(id, type, row, col) struct('Id',id, 'Type',type, 'Label','', ...
    'Row',row, 'Col',col, 'PopOut',false, 'Options',struct());
bs.Regions(end+1) = mk('R1', 'gui.components.ModeIndicator', [1 1], [1 1]);
bs.Regions(end+1) = mk('R2', 'gui.components.ModeIndicator', [1 1], [2 2]);
bs.Regions(end+1) = mk('R3', 'gui.components.SessionClock',  [2 2], [1 1]);
bs.Regions(end+1) = mk('R4', 'gui.components.SessionClock',  [2 2], [2 2]);
bs  = gui.BehaviorBuilder.specValidate(bs);
src = gui.BehaviorBuilder.generateCode(bs, '');
miLines = src(contains(src, 'gui.components.ModeIndicator'));
scLines = src(contains(src, 'gui.components.SessionClock'));
assert(numel(miLines) == 2 && numel(scLines) == 2, ...
    'every dotted-Type region must be emitted (got %d + %d)', numel(miLines), numel(scLines));
assert(~any(contains(miLines, 'PreferenceTag')), ...
    'a class with no PreferenceTag option must not be handed one when placed twice');
assert(all(contains(scLines, 'PreferenceTag=')), ...
    'a class that declares PreferenceTag must get a unique one per placement');
fprintf('PASS: dotted Types validate and generate; PreferenceTag follows the spec\n');

%% 11. Teardown -------------------------------------------------------------
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
% A governor and its dependent, for the EnabledBy regression.
p = sw.add_parameter('SmokeGate', false, Type='Boolean'); p.Value = false;
p = sw.add_parameter('SmokeGated', 0.2);                  p.Value = 0.2;
rt.Interfaces = sw;
end


function cleanupAll(prefTag)
if ispref(prefTag)
    rmpref(prefTag);
end
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
end


function cleanupLate(lateDir, lateFile)
% Take the late-arriving class back off the path and disk, and forget it,
% so a rerun in the same session starts from a genuine miss.
try
    rmpath(lateDir);
catch
end
if isfile(lateFile), delete(lateFile); end
if isfolder(lateDir), rmdir(lateDir, 's'); end
gui.ComponentSpec.flushCache();
end
