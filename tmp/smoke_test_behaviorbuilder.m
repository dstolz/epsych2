function smoke_test_behaviorbuilder()
% smoke_test_behaviorbuilder()
% Exercise gui.BehaviorBuilder's headless surface: the layout-spec round
% trip (save -> load -> exact), the validation tripwires (overlap, psych
% gating), the code generator (lint-clean output, correct class shape,
% PreferenceTag uniquing), and the generated GUIs themselves - constructed
% against a software runtime and against the empty runtime SelfTest I6
% uses. The builder window/canvas is covered separately once constructed;
% this file must pass with no display interaction.
%
%   matlab -batch "run('tmp/smoke_test_behaviorbuilder.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

outDir = fullfile(tempdir, 'epsych_builder_smoke');
if ~exist(outDir,'dir'), mkdir(outDir); end
addpath(outDir);
cleanupObj = onCleanup(@() cleanupAll(outDir)); %#ok<NASGU>

% 1. Spec round trip ------------------------------------------------------
specA = buildSpecA();
canonical = gui.BehaviorBuilder.specValidate(specA);
specFile = fullfile(outDir, 'TmpBuilderTestGUI.eblt');
gui.BehaviorBuilder.saveSpecFile(canonical, specFile);
loaded = gui.BehaviorBuilder.loadSpecFile(specFile);
assert(isequaln(canonical, loaded), 'spec round trip must be exact');
fprintf('PASS: spec save/load round trip is exact\n');

% 2. Validation tripwires -------------------------------------------------
bad = canonical;
bad.Regions(1).Row = [1 4]; % control column grows into the button row
mustReject(bad, 'epsych:BehaviorBuilder:Overlap');
bad = canonical;
bad.Psych.Type = 'none';    % History/StaircasePlot regions depend on it
mustReject(bad, 'epsych:BehaviorBuilder:NeedsPsych');
bad = canonical;
bad.ClassName = '2BadName';
mustReject(bad, 'epsych:BehaviorBuilder:BadClassName');
bad = canonical;
bad.Regions(1).Col = [1 99];
mustReject(bad, 'epsych:BehaviorBuilder:BadRegion');
fprintf('PASS: validation rejects overlap, psych removal, bad names, bad spans\n');

% 3. Code generation ------------------------------------------------------
mFile = gui.BehaviorBuilder.writeCode(canonical, specFile);
msgs = checkcode(mFile);
assert(isempty(msgs), 'generated file must be lint-clean:%s', formatMsgs(msgs));
txt = fileread(mFile);
assert(contains(txt, 'obj.addUpdateButton'), 'update button must be emitted for editable controls');
assert(numel(strfind(txt, 'PreferenceTag=''TmpBuilderTestGUI_')) >= 2, ...
    'both Monitor instances must get unique PreferenceTags');
assert(~contains(txt, 'function delete'), 'generated class must not emit a destructor');
assert(~contains(txt, 'closeGUI'), 'generated class must not emit closeGUI');

rehash % the file appeared after addpath; refresh the path cache
clear('TmpBuilderTestGUI') % pick up the fresh file if a stale class is cached
mc = meta.class.fromName('TmpBuilderTestGUI');
assert(~isempty(mc), 'generated class must resolve');
assert(any(strcmp({mc.SuperclassList.Name}, 'gui.BehaviorGUI')), ...
    'generated class must subclass gui.BehaviorGUI');
ml = mc.MethodList;
ix = strcmp({ml.Name}, 'build');
assert(any(ix) && strcmp(ml(ix).Access, 'protected'), ...
    'build must exist with protected access');
assert(strcmp(TmpBuilderTestGUI.LayoutSpecFile, specFile), ...
    'LayoutSpecFile constant must record the spec path');
fprintf('PASS: codegen output is lint-clean with the right class shape\n');

% 4. Generated GUI against a software runtime -----------------------------
rt = makeRuntimeA();
g = TmpBuilderTestGUI(rt);
assert(isvalid(g) && isvalid(g.h_figure), 'generated GUI must construct');
assert(isa(g.Psych, 'psychophysics.Staircase'), 'createPsych must build the staircase');
assert(isfield(g.hButtons, 'DropPellet'), 'button row must create trigger buttons');
% (event payload semantics are the components' own contract, covered by
% smoke_test_behaviorgui and the screenshot generator's full session)
fig = g.h_figure;
delete(g);
assert(~isvalid(fig), 'teardown must remove the figure');
t = timerfindall;
if ~isempty(t)
    assert(~any(startsWith({t.Name}, 'Parameter_Monitor_Timer')), ...
        'no monitor timers may survive teardown');
end
fprintf('PASS: generated GUI constructs and tears down\n');

% 5. Empty-runtime launch (SelfTest I6 semantics) -------------------------
rtE = epsych.Runtime;
rtE.isTest = true;
rtE.EVENTS = epsych.EventHub;
g2 = TmpBuilderTestGUI(rtE);
assert(isvalid(g2) && isvalid(g2.h_figure), ...
    'generated GUI must open against a runtime with no interfaces');
assert(isempty(g2.Psych), 'createPsych must return [] when the parameter is absent');
delete(g2);
fprintf('PASS: empty-runtime launch survives (SelfTest I6)\n');

% 6. Auxiliary component set (clock/timer/mode/pump/psychplot/capture) ----
specB = buildSpecB();
specFileB = fullfile(outDir, 'TmpBuilderAuxGUI.eblt');
gui.BehaviorBuilder.saveSpecFile(specB, specFileB);
mFileB = gui.BehaviorBuilder.writeCode(specB, specFileB);
msgs = checkcode(mFileB);
assert(isempty(msgs), 'aux generated file must be lint-clean:%s', formatMsgs(msgs));
rehash
clear('TmpBuilderAuxGUI')
rtB = makeRuntimeB();
gb = TmpBuilderAuxGUI(rtB);
assert(isvalid(gb) && isvalid(gb.h_figure), 'aux GUI must construct');
assert(isa(gb.Psych, 'psychophysics.Detection'), 'createPsych must build the Detection object');
delete(gb);
fprintf('PASS: aux components (clock, timer, mode, pump, psych plot, capture)\n');

% 6b. Session notes: both forms, from one spec ----------------------------
specC = buildSpecC();
specFileC = fullfile(outDir, 'TmpBuilderNotesGUI.eblt');
gui.BehaviorBuilder.saveSpecFile(specC, specFileC);
mFileC = gui.BehaviorBuilder.writeCode(specC, specFileC);
msgs = checkcode(mFileC);
assert(isempty(msgs), 'notes generated file must be lint-clean:%s', formatMsgs(msgs));

srcC = fileread(mFileC);
assert(contains(srcC, 'obj.addNotes('), 'the panel form must emit addNotes');
assert(contains(srcC, 'obj.addNotesButton('), 'the button form must emit addNotesButton');
assert(contains(srcC, 'TimeStamp="clock"'), 'a non-default stamp must be emitted');
assert(count(srcC, 'PreferenceTag=') >= 2, ...
    'two gui.components.Notes in one GUI must get uniqued preference tags');
assert(~contains(srcC, 'addPopOutButton'), ...
    'the button form is its own pop-out opener, so no pop-out button is emitted');

rehash
clear('TmpBuilderNotesGUI')
rtC = makeRuntimeB();
gc = TmpBuilderNotesGUI(rtC);
assert(isvalid(gc) && isvalid(gc.h_figure), 'notes GUI must construct');

% The generated class keeps no handles, so the components are found in the
% window: one log box (the panel form) and a labelled button (the button form).
logs = findall(gc.h_figure, 'Type','uitextarea');
assert(isscalar(logs), 'the panel form must build exactly one log box');
btns = findall(gc.h_figure, 'Type','uibutton');
assert(any(strcmp({btns.Text}, 'Session Log')), ...
    'the button form must build a button carrying the configured label');

rtC.NOTES.add('typed while the generated GUI is open');
assert(numel(logs.Value) == 1 && contains(logs.Value{1}, 'typed while'), ...
    'the panel must show a note added through the runtime store');
assert(contains(logs.Value{1}, ':'), 'the configured clock stamp must be rendered');
delete(gc);
fprintf('PASS: session notes place, generate, and run in both forms\n');

% 7. Builder window over the round-tripped spec --------------------------
b = gui.BehaviorBuilder;
assert(isvalid(b), 'builder window must construct');
b.openSpec(specFile);
assert(strcmp(b.Spec.ClassName, 'TmpBuilderTestGUI'), 'openSpec must load the spec');
assert(~b.Dirty, 'a freshly opened spec must not be dirty');
nRegions = numel(b.Spec.Regions);
rois = findall(groot, 'Type','images.roi.rectangle');
assert(numel(rois) == nRegions, ...
    'canvas must draw one ROI per region (got %d, want %d)', numel(rois), nRegions);
m = gui.BehaviorBuilder.ROI_INSET; % ROIs sit inset inside whole grid cells
for k = 1:numel(rois)
    p = rois(k).Position;
    cells = [p(1)-m, p(2)-m, p(3)+2*m, p(4)+2*m];
    assert(all(abs(cells - round(cells)) < 1e-9), ...
        'ROI positions must sit on whole grid cells (inset by ROI_INSET)');
end
% programmatic placement path (no-options type opens no dialog)
b.addRegion('SessionClock', [1 1], [4 4]); % the one free cell
assert(numel(b.Spec.Regions) == nRegions + 1, 'addRegion must append');
assert(b.Dirty, 'placement must mark the spec dirty');
b.removeRegion(b.Spec.Regions(end).Id);
assert(numel(b.Spec.Regions) == nRegions, 'removeRegion must remove');
delete(b);
assert(isempty(findall(groot,'Type','figure','-and','Tag',gui.BehaviorBuilder.PREF_TAG)), ...
    'builder teardown must close its window');
fprintf('PASS: builder window opens a spec, draws snapped ROIs, places/removes\n');

fprintf('smoke_test_behaviorbuilder: ALL PASS\n');
end


% =========================================================================
function spec = buildSpecA()
spec = gui.BehaviorBuilder.specNew;
spec.ClassName  = 'TmpBuilderTestGUI';
spec.WindowName = 'Builder Smoke Test';
spec.Psych.Type = 'Staircase';
spec.Psych.Parameter = 'Depth';

sw = makeInterfaceA();
spec.ProtocolPath = ''; % spec built programmatically, no .eprot on disk
spec.ParameterSnapshot = gui.BehaviorBuilder.snapshotFromParameters( ...
    sw.all_parameters(includeTriggers=true));
delete(sw);

ctrl = gui.BehaviorBuilder.defaultOptions('ControlColumn');
ctrl.Controls = struct( ...
    'Param',      {'ITIDur','TimeoutDur','Depth','InTrial'}, ...
    'Type',       {'auto','auto','auto','readonly'}, ...
    'autoCommit', {false, true, false, false}, ...
    'Text',       {'Intertrial Interval (s)','','',''});
spec = addRegion(spec, 'R1', 'ControlColumn', 'Trial Controls', [2 4], [1 1], false, ctrl);

btn = gui.BehaviorBuilder.defaultOptions('ButtonRow');
btn.Buttons = struct('Param', {'DropPellet','~TrialDelivery'}, 'Text', {'Pellet',''});
btn.IncludeScreenCapture = true;
spec = addRegion(spec, 'R2', 'ButtonRow', '', [1 1], [1 3], false, btn);

mon = gui.BehaviorBuilder.defaultOptions('Monitor');
mon.Params = {'InTrial','RespCode'};
mon.PollPeriod = 0.5;
spec = addRegion(spec, 'R3', 'Monitor', 'Monitor', [2 2], [2 2], true, mon);

sca = gui.BehaviorBuilder.defaultOptions('Scatter');
sca.YParameter = 'Depth';
spec = addRegion(spec, 'R4', 'Scatter', 'Trial History', [3 4], [2 2], false, sca);

spec = addRegion(spec, 'R5', 'StaircasePlot', 'Staircase', [2 3], [3 3], false, ...
    gui.BehaviorBuilder.defaultOptions('StaircasePlot'));
spec = addRegion(spec, 'R6', 'History', 'Trials', [4 4], [3 3], false, ...
    gui.BehaviorBuilder.defaultOptions('History'));
spec = addRegion(spec, 'R7', 'NextTrial', 'Next Trial', [2 2], [4 4], false, ...
    gui.BehaviorBuilder.defaultOptions('NextTrial'));
spec = addRegion(spec, 'R8', 'Performance', 'Performance', [3 3], [4 4], false, ...
    gui.BehaviorBuilder.defaultOptions('Performance'));

mon2 = gui.BehaviorBuilder.defaultOptions('Monitor');
mon2.Params = {'TrialCount'};
spec = addRegion(spec, 'R9', 'Monitor', 'Counts', [4 4], [4 4], false, mon2);
end

function spec = buildSpecB()
spec = gui.BehaviorBuilder.specNew;
spec.ClassName  = 'TmpBuilderAuxGUI';
spec.WindowName = 'Builder Aux Smoke Test';
spec.Grid.Rows = 3; spec.Grid.Cols = 3;
spec.Grid.RowHeight   = {'40','1x','1x'};
spec.Grid.ColumnWidth = {'1x','1x','1x'};
spec.Psych.Type = 'Detection';
spec.Psych.Parameter = 'dBSPL';
spec.Psych.TargetTrialType = 'TrialType_0';

sw = makeInterfaceB();
spec.ParameterSnapshot = gui.BehaviorBuilder.snapshotFromParameters( ...
    sw.all_parameters(includeTriggers=true));
delete(sw);

spec = addRegion(spec, 'R1', 'SessionClock', 'Clock', [1 1], [1 1], false, ...
    gui.BehaviorBuilder.defaultOptions('SessionClock'));
spec = addRegion(spec, 'R2', 'TrialTimer', 'Trial Timer', [1 1], [2 2], false, ...
    gui.BehaviorBuilder.defaultOptions('TrialTimer'));
spec = addRegion(spec, 'R3', 'ScreenCapture', '', [1 1], [3 3], false, ...
    gui.BehaviorBuilder.defaultOptions('ScreenCapture'));
pump = gui.BehaviorBuilder.defaultOptions('SyringePump');
spec = addRegion(spec, 'R4', 'SyringePump', 'Reward Pump', [2 3], [1 1], true, pump);
spec = addRegion(spec, 'R5', 'PsychPlot', 'Psychometric', [2 3], [2 2], false, ...
    gui.BehaviorBuilder.defaultOptions('PsychPlot'));
spec = addRegion(spec, 'R6', 'ModeIndicator', 'Mode', [2 2], [3 3], false, ...
    gui.BehaviorBuilder.defaultOptions('ModeIndicator'));
spec = addRegion(spec, 'R7', 'NextTrial', 'Next Trial', [3 3], [3 3], false, ...
    gui.BehaviorBuilder.defaultOptions('NextTrial'));
end

function spec = buildSpecC()
% Both notes forms in one GUI: the pad, and a button that opens its own
% window. The button region carries PopOut=true on purpose -- validation must
% clear it, since that button IS the pop-out opener.
spec = gui.BehaviorBuilder.specNew;
spec.ClassName  = 'TmpBuilderNotesGUI';
spec.WindowName = 'Builder Notes Smoke Test';
spec.Grid.Rows = 2; spec.Grid.Cols = 1;
spec.Grid.RowHeight   = {'1x','40'};
spec.Grid.ColumnWidth = {'1x'};

sw = makeInterfaceB();
spec.ParameterSnapshot = gui.BehaviorBuilder.snapshotFromParameters( ...
    sw.all_parameters(includeTriggers=true));
delete(sw);

pad = gui.BehaviorBuilder.defaultOptions('Notes');
pad.TimeStamp = 'clock';
pad.Editable  = true;
spec = addRegion(spec, 'N1', 'Notes', 'Notes', [1 1], [1 1], false, pad);

btn = gui.BehaviorBuilder.defaultOptions('Notes');
btn.ButtonOnly = true;
btn.Text = 'Session Log';
spec = addRegion(spec, 'N2', 'Notes', '', [2 2], [1 1], true, btn);

spec = gui.BehaviorBuilder.specValidate(spec);
assert(~spec.Regions(2).PopOut, ...
    'the button form must have its pop-out flag cleared by validation');
end

function spec = addRegion(spec, id, type, label, rowSpan, colSpan, popOut, options)
spec.Regions(end+1) = struct('Id',id, 'Type',type, 'Label',label, ...
    'Row',rowSpan, 'Col',colSpan, 'PopOut',popOut, 'Options',options);
end

function sw = makeInterfaceA()
% Software stand-ins for the parameters specA references (run_example idiom:
% add_parameter fills Values, so assign the live Value explicitly).
sw = hw.Software;
p = sw.add_parameter('DropPellet', 0, isTrigger=true);         p.Value = 0;
p = sw.add_parameter('~TrialDelivery', false, Type='Boolean'); p.Value = false;
p = sw.add_parameter('ITIDur', 5, Unit='s');                   p.Value = 5;
p = sw.add_parameter('TimeoutDur', 8, Unit='s');               p.Value = 8;
p = sw.add_parameter('Depth', 50, Unit='%');                   p.Value = 50;
p = sw.add_parameter('InTrial', false, Type='Boolean');        p.Value = false; p.Access = 'Read';
p = sw.add_parameter('RespCode', 0);                           p.Value = 0;     p.Access = 'Read';
p = sw.add_parameter('TrialCount', 0);                         p.Value = 0;     p.Access = 'Read';
end

function sw = makeInterfaceB()
sw = hw.Software;
p = sw.add_parameter('dBSPL', 60, Unit='dB SPL'); p.Value = 60;
p = sw.add_parameter('RespCode', 0);              p.Value = 0; p.Access = 'Read';
end

function rt = makeRuntimeA()
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
rt.Interfaces = makeInterfaceA();
end

function rt = makeRuntimeB()
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
rt.Interfaces = makeInterfaceB();
end

function mustReject(spec, wantId)
try
    gui.BehaviorBuilder.specValidate(spec);
    error('epsych:BehaviorBuilder:TestFail', ...
        'spec should have been rejected with %s', wantId)
catch ME
    assert(strcmp(ME.identifier, wantId), ...
        'expected %s, got %s (%s)', wantId, ME.identifier, ME.message)
end
end

function s = formatMsgs(msgs)
s = '';
for i = 1:numel(msgs)
    s = sprintf('%s\n  L%d: %s', s, msgs(i).line, msgs(i).message);
end
end

function cleanupAll(outDir)
% Close stray test figures, then remove the scratch folder. The builder's
% own position pref is left alone (a real one may exist on this machine).
delete(findall(groot, 'Type','figure', '-and', 'Tag', gui.BehaviorBuilder.PREF_TAG));
for tag = {'TmpBuilderTestGUI','TmpBuilderAuxGUI'}
    delete(findall(groot, 'Type','figure', '-and', 'Tag', tag{1}));
    if ispref(tag{1})
        rmpref(tag{1});
    end
end
rmpath(outDir);
if exist(outDir, 'dir')
    try %#ok<TRYNC>
        rmdir(outDir, 's');
    end
end
end
