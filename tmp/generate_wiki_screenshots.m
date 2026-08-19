function generate_wiki_screenshots(options)
% generate_wiki_screenshots(Name=Value, ...)
% Regenerate the full-window GUI screenshots the wiki embeds, so the images
% track the current UI. Each shot reproduces the scenario its published
% caption describes; read the caption before changing a shot.
%
% Companion to generate_component_screenshots, which captures the individual
% obj/+gui components for the Behavior GUI Components page.
%
% Options:
%   OutputDir - Wiki images folder (default: ../epsych2.wiki/images)
%   Only      - Capture just these shot names (default: all)
%
%   generate_wiki_screenshots(Only=["ProtocolDesigner","CompiledPreview"])
%
% Shots that also have a copy inside this repository (documentation/) are
% written to both places, because the two drift apart otherwise.

arguments
    options.OutputDir (1,:) char = ''
    options.Only (1,:) string = string.empty(1,0)
end

here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(here);
run(fullfile(repoRoot, 'epsych_startup.m'));
addpath(here);
addpath(fullfile(repoRoot, 'examples', 'detection_task'));
addpath(fullfile(repoRoot, 'examples', 'customgui'));
addpath(fullfile(repoRoot, 'examples', 'two_afc'));

if isempty(options.OutputDir)
    options.OutputDir = fullfile(fileparts(repoRoot), 'epsych2.wiki', 'images');
end
if ~isfolder(options.OutputDir), error('No wiki images folder at %s', options.OutputDir); end

C = struct('repoRoot', repoRoot, 'here', here, 'outDir', options.OutputDir, ...
    'protocol', fullfile(repoRoot, 'examples', 'detection_task', 'DetectionExample.eprot'), ...
    'scratch', fullfile(tempdir, 'epsych_wiki_shots'));
if ~isfolder(C.scratch), mkdir(C.scratch); end

% Second home for the shots the repository also publishes.
alsoIn = struct( ...
    'ProtocolDesigner',            fullfile(repoRoot, 'documentation', 'design', 'images'), ...
    'ProtocolDesigner_Interfaces', fullfile(repoRoot, 'documentation', 'design', 'images'), ...
    'RunExpt',                     fullfile(repoRoot, 'documentation', 'overviews', 'images'), ...
    'SubjectManager',              fullfile(repoRoot, 'documentation', 'gui', 'images'), ...
    'BehaviorBuilder',             fullfile(repoRoot, 'documentation', 'gui', 'images'));

shots = { ...
    'ProtocolDesigner',  @shotProtocolDesigner; ...
    'ProtocolDesigner_Interfaces', @shotProtocolDesignerInterfaces; ...
    'CompiledPreview',   @shotCompiledPreview; ...
    'ParameterWidgets',  @shotParameterWidgets; ...
    'ParameterScatter',  @shotParameterScatter; ...
    'OnlineAnalysis',    @shotOnlineAnalysis; ...
    'StaircaseTraining', @shotStaircaseTraining; ...
    'ExampleBehaviorGUI',     @shotExampleBehaviorGUI; ...
    'DetectionBehaviorGUI',   @shotDetectionBehaviorGUI; ...
    'TwoAFCBehaviorGUI',          @shotTwoAFCBehaviorGUI; ...
    'TwoAFCBehaviorGUI_feedback', @shotTwoAFCBehaviorGUIFeedback; ...
    'TwoAFCBehaviorGUI_scatter',  @shotTwoAFCBehaviorGUIScatter; ...
    'BehaviorBuilder',            @shotBehaviorBuilder; ...
    'BehaviorBuilder_Generated',  @shotBehaviorBuilderGenerated; ...
    'RunExpt',           @shotRunExpt; ...
    'SubjectManager',    @shotSubjectManager; ...
    'SelfTest',          @shotSelfTest; ...
    'StimPlayer',        @shotStimPlayer; ...
    'CalibrationGui',    @shotCalibrationGui; ...
    'TeensyTrialDesigner',        @shotTeensyChannels; ...
    'TeensyTrialDesigner_States', @shotTeensyStates; ...
    'TeensyTestBench',            @shotTeensyTestBench; ...
    };

names = string(shots(:,1));
if ~isempty(options.Only)
    keep = ismember(names, options.Only);
    if ~any(keep)
        error('generate_wiki_screenshots:UnknownShot', ...
            'No shot matches %s. Available: %s', strjoin(options.Only,', '), strjoin(names,', '));
    end
    shots = shots(keep,:);
end

prefs = snapshotPrefs();
restore = onCleanup(@() restorePrefs(prefs));

nFail = 0;
for k = 1:size(shots,1)
    name = shots{k,1};
    cleanupFcn = [];
    try
        [fig, cleanupFcn] = shots{k,2}(C);
        drawnow; pause(0.5); drawnow
        outFile = fullfile(C.outDir, [name '.png']);
        exportapp(fig, outFile);
        if isfield(alsoIn, name) && isfolder(alsoIn.(name))
            copyfile(outFile, fullfile(alsoIn.(name), [name '.png']));
        end
        d = dir(outFile);
        fprintf('  %-20s %6.1f KB  %s\n', name, d.bytes/1024, outFile);
    catch ME
        nFail = nFail + 1;
        fprintf(2, '  %-20s FAILED: %s (%s)\n', name, ME.message, topFrame(ME));
    end
    if ~isempty(cleanupFcn)
        try, cleanupFcn(); catch, end   %#ok<NOCOM>
    end
    drawnow
end

fprintf('\n%d of %d shots written to %s\n', size(shots,1)-nFail, size(shots,1), C.outDir);
end


%% ------------------------------------------------------------------------
%  Protocol design
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotProtocolDesigner(C)
% Caption: "one Software interface holding thirteen parameters", ToneLevel
% with five values, RespWinDelay driven by an expression, ITI randomized.
pd = openDesigner(C);
fig = pd.Figure;
fig.Position(3:4) = [1360 720];
cleanupFcn = @() closeDesigner(pd);
end


function [fig, cleanupFcn] = shotProtocolDesignerInterfaces(C)
% The interfaces/modules tree that moved out of the main window into its own
% dialog, alongside the Add Interface builder.
pd = openDesigner(C);
pd.onOpenInterfaceDialog();
drawnow
fig = pd.InterfaceFigure;
cleanupFcn = @() closeDesigner(pd);
end


function [fig, cleanupFcn] = shotCompiledPreview(C)
% Caption: the trial list the protocol expands into - six conditions.
pd = openDesigner(C);
pd.onOpenCompiledPreviewDialog();
drawnow
fig = pd.PreviewFigure;
fig.Position(3:4) = [1000 400];
cleanupFcn = @() closeDesigner(pd);
end


function pd = openDesigner(C)
% The column view is a saved user preference; pin it for a reproducible image.
setpref('ProtocolDesigner', 'TableViewMode', 'Detailed');
pd = epsych.ProtocolDesigner.openFromFile(C.protocol);
drawnow
end


function closeDesigner(pd)
h = struct(pd);
figs = {h.Figure, h.InterfaceFigure, h.OptionsFigure, h.PreviewFigure, h.CheckCalcFigure};
for i = 1:numel(figs)
    if ~isempty(figs{i}) && isvalid(figs{i}), delete(figs{i}); end
end
end


%% ------------------------------------------------------------------------
%  Parameter widgets
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotParameterWidgets(C)
% Caption: three Parameter_Controls under one Parameter_Update button (all
% unedited, so the button is idle), a graphical Parameter_Monitor, and a
% PhaseSelector with Load greyed until a phase is chosen.
rt = softwareRuntime(C);

phaseDir = fullfile(C.scratch, 'phases');
if ~isfolder(phaseDir), mkdir(phaseDir); end
for nm = ["Shaping","Training_Easy","Training_Hard","Testing"]
    dst = fullfile(phaseDir, nm + ".eprot");
    if ~isfile(dst), copyfile(C.protocol, dst); end
end

fig = uifigure('Visible', 'off', 'Position', [200 200 900 250], 'Tag', 'wikiShot');
g = uigridlayout(fig, [1 3]);
g.ColumnWidth = {'1.1x', '0.9x', '1x'};

left = uipanel(g, 'Title', 'Parameter Controls');
lg = uigridlayout(left, [4 1]);
lg.RowHeight = {32, 32, 32, 36};
c1 = gui.Parameter_Control(lg, rt.find_parameter('ToneFreq'),  Text='Tone Frequency (Hz)');
c2 = gui.Parameter_Control(lg, rt.find_parameter('ToneDur'),   Text='Tone Duration (ms)');
c3 = gui.Parameter_Control(lg, rt.find_parameter('RewardVol'), Text='Reward Volume (uL)');
U = gui.Parameter_Update(rt, lg);
U.watchedHandles = [c1 c2 c3];

mid = uipanel(g, 'Title', 'Parameter Monitor');
mg = uigridlayout(mid, [1 1]);
mg.Padding = [2 2 2 2];
setReadValue(rt.find_parameter('InTrial'), true);
gui.Parameter_Monitor(mg, [rt.find_parameter('InTrial'), rt.find_parameter('ToneLevel'), ...
    rt.find_parameter('ToneFreq'), rt.find_parameter('ToneDur')], ...
    type='graphical', pollPeriod=0.5, PreferenceTag="wikiShotWidgetsMonitor");

right = uipanel(g, 'Title', 'Phase Selector');
ps = gui.PhaseSelector(rt, phaseDir);
ps.PhasePath = phaseDir;
ps.createGUI(right);

cleanupFcn = @() delete(ps);
end


%% ------------------------------------------------------------------------
%  Online analysis
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotParameterScatter(C)
% Caption: tone level against trial number for a 150-trial session, colored
% by the decoded response.
S = detectionSession(C);
fig = uifigure('Visible', 'off', 'Position', [200 200 760 440], 'Tag', 'wikiShot');
gui.ParameterScatter(S.DATA, fig, PreferenceTag='wikiShotScatterBig', ...
    XParameter='TrialIndex', YParameter='ToneLevel', ColorParameter='Response');
cleanupFcn = @() delete(S.Psych);
end


function [fig, cleanupFcn] = shotOnlineAnalysis(C)
% Caption: gui.History, gui.Performance and gui.PsychPlot side by side, all
% fed from the same 150-trial detection session.
S = detectionSession(C);
sc = psychophysics.Staircase(S.DATA, S.Level);

fig = uifigure('Visible', 'off', 'Position', [200 200 1200 380], 'Tag', 'wikiShot');
g = uigridlayout(fig, [1 3]);
g.ColumnWidth = {'1.1x', '1x', '1x'};

pHist = uipanel(g, 'Title', 'gui.History');
H = gui.History(sc, pHist, PreferenceTag='wikiShotOnlineHistory');
H.BitColors              = ["#c8ffd9","#ffcdcd","#b3e1ff","#ffeacf","#faffcc"];
H.ParametersOfInterest   = {'ToneLevel','TrialType'};
H.ParameterColumnFormats = {'%g','%d'};
H.update();

pPerf = uipanel(g, 'Title', 'gui.Performance');
P = gui.Performance(S.Psych, pPerf);
P.ParametersOfInterest = {'ToneLevel'};

pPsych = uipanel(g, 'Title', 'gui.PsychPlot');
gui.PsychPlot(S.Psych, axes(pPsych));

S.RUNTIME.EVENTS.notify('NewData', S.TrialsEvent);
cleanupFcn = @() cleanupAnalysis(S, sc);
end


function cleanupAnalysis(S, sc)
delete(sc); delete(S.Psych);
end


function [fig, cleanupFcn] = shotStaircaseTraining(C)
% Caption: step rules for one parameter, with the value history below.
rt = softwareRuntime(C);
fig = uifigure('Visible', 'off', 'Position', [200 200 620 380], 'Tag', 'wikiShot');
st = gui.StaircaseTraining(rt.find_parameter('ToneLevel'), Parent=fig, ...
    MinValue=10, MaxValue=70, StepUp=2, StepDown=5, ...
    StepUpResponse="Hit", StepDownResponse="Miss");
cleanupFcn = @() delete(st);
end


%% ------------------------------------------------------------------------
%  Behavior GUIs
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotExampleBehaviorGUI(C)
% Caption: the template running against a software-only runtime, before any
% trials.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
sw = hw.Software;
p = sw.add_parameter('DropPellet', 0, isTrigger=true);          p.Value = 0;
p = sw.add_parameter('~TrialDelivery', false, Type='Boolean');  p.Value = false;
p = sw.add_parameter('ITIDur', 5, Unit='s');                    p.Value = 5;
p = sw.add_parameter('TimeoutDur', 8, Unit='s');                p.Value = 8;
p = sw.add_parameter('Depth', 50, Unit='%');                    p.Value = 50;
p = sw.add_parameter('dBSPL', 60, Unit='dB SPL');               p.Value = 60;
p = sw.add_parameter('InTrial', false, Type='Boolean');         p.Value = false; p.Access = 'Read';
p = sw.add_parameter('RespCode', 0);                            p.Value = 0;     p.Access = 'Read';
p = sw.add_parameter('TrialCount', 0);                          p.Value = 0;     p.Access = 'Read';
rt.Interfaces = sw;

G = ExampleBehaviorGUI(rt);
fig = G.h_figure;
cleanupFcn = @() delete(G);
end


function [fig, cleanupFcn] = shotDetectionBehaviorGUI(C)
% Caption: after 150 simulated trials, ending in Mode: Stop.
closeByTag('DetectionBehaviorGUI');
RUNTIME = run_detection_session(NumTrials=150, ShowGUI=true, ...
    DataPath=C.scratch, Seed=7);
fig = findall(groot, 'Type', 'figure', '-and', 'Tag', 'DetectionBehaviorGUI');
fig = fig(1);
G = fig.UserData;
cleanupFcn = @() delete(G);
end


function [fig, cleanupFcn] = shotTwoAFCBehaviorGUI(C)
% Caption: mid-stimulus on an early trial, both fields lit and one
% brighter. FlashDur is stretched to 2500 ms so the flash is visible in a
% still image -- the default is 150 ms, brief enough that you have to be
% watching.
[RUNTIME, GUI] = twoAFCShotSession(C, 'wikiShotAFCStim', ...
    FlashDur = 2500, RespWinDur = 4000, NumTrials = 3);
ok = waitForCond(@() ~isPatchDark(GUI.LeftPatch) || ~isPatchDark(GUI.RightPatch), 5);
assert(ok, 'stimulus never lit for the mid-stimulus shot');
fig = GUI.h_figure;
cleanupFcn = @() stopTwoAFCShot(RUNTIME, GUI);
end


function [fig, cleanupFcn] = shotTwoAFCBehaviorGUIFeedback(C)
% Caption: just after answering correctly -- both buttons disarmed, the
% fields dark again, and the NAFC choice plot updated.
[RUNTIME, GUI] = twoAFCShotSession(C, 'wikiShotAFCFeedback', ...
    FlashDur = 2500, RespWinDur = 4000, NumTrials = 3);
ok = waitForCond(@() logical(GUI.LeftButton.Enable), 5);
assert(ok, 'response window never armed for the feedback shot');
T = RUNTIME.TRIALS(1);
correctSide = T.trials{T.NextTrialID, T.writeParamIdx.TrialType};
GUI.respondSide(double(correctSide));
ok = waitForCond(@() strcmp(GUI.FeedbackLabel.Text, 'CORRECT'), 3);
assert(ok, 'feedback label never showed CORRECT');
fig = GUI.h_figure;
cleanupFcn = @() stopTwoAFCShot(RUNTIME, GUI);
end


function [fig, cleanupFcn] = shotTwoAFCBehaviorGUIScatter(C)
% Caption: the operator's mid-session view -- the per-trial "Signed
% Contrast by Chosen Side" scatter and the psychophysics.NAFC choice plot
% below it, both populated. Kept fast (short flash/response/ITI) so the
% whole shot finishes in well under a minute even on a busy shared MATLAB
% session.
%
% 72 trials, not 24: the choice plot draws P(chose k) per unique
% SignedContrast, and the protocol crosses 2 sides x 4 contrasts, so 24
% trials leave 3 per point and every proportion is 0, 1/3, 2/3 or 1 -- a
% zigzag between the rails that says nothing about the subject. Nine
% trials per point is the least that reads as a curve.
NTRIALS = 72;
[RUNTIME, GUI] = twoAFCShotSession(C, 'wikiShotAFCScatter', ...
    FlashDur = 60, RespWinDur = 400, ITIRange = [60 120], NumTrials = NTRIALS);
rng(11);
watchdog = tic;
while strcmp(RUNTIME.TIMER.Running, 'on') && toc(watchdog) < 120
    pause(0.02) % timers fire during pause; this is the session's event pump
    if ~isvalid(GUI) || ~logical(GUI.LeftButton.Enable), continue; end
    T = RUNTIME.TRIALS(1);
    correctSide = T.trials{T.NextTrialID, T.writeParamIdx.TrialType};
    % Accuracy rises with contrast, so the choice plot shows the sigmoid it
    % exists to show rather than one flat rate at every difficulty. A fixed
    % 82% would make the panel look broken to anyone who knows what a
    % psychometric function does.
    contrast = T.trials{T.NextTrialID, T.writeParamIdx.Contrast};
    pCorrect = 0.5 + 0.48 * (abs(contrast) / 0.32) ^ 0.8;
    if rand < pCorrect
        side = correctSide;
    else
        side = 1 - correctSide;
    end
    GUI.respondSide(double(side));
end
assert(strcmp(RUNTIME.TIMER.Running, 'off'), ...
    'scatter-shot session did not auto-stop within the watchdog window');
fig = GUI.h_figure;
cleanupFcn = @() stopTwoAFCShot(RUNTIME, GUI);
end


function [RUNTIME, GUI] = twoAFCShotSession(C, tag, options)
% Build a fresh TwoAFC protocol with shot-specific timing and start a real
% timer-loop session against it, exactly as run_2afc_experiment does. A
% distinct tag per shot keeps scratch protocol/data files from colliding
% when shots run back to back.
arguments
    C
    tag (1,:) char
    options.FlashDur (1,1) double = 150
    options.RespWinDur (1,1) double = 3000
    options.ITIRange (1,2) double = [800 1800]
    options.NumTrials (1,1) double = 8
end
closeByTag('TwoAFCBehaviorGUI');
protFile = fullfile(C.scratch, [tag '.eprot']);
create_2afc_protocol(protFile, FlashDur = options.FlashDur, ...
    RespWinDur = options.RespWinDur, ITIRange = options.ITIRange);
[RUNTIME, GUI] = run_2afc_experiment(NumTrials = options.NumTrials, ...
    ProtocolFile = protFile, DataPath = fullfile(C.scratch, tag), ...
    SubjectName = 'WikiShot', Test = true);
drawnow
end


function tf = isPatchDark(p)
tf = isequal(round(p.BackgroundColor, 3), [0.06 0.06 0.06]);
end


function tf = waitForCond(cond, timeoutSec)
% Poll a condition function during pause() -- timers fire while paused --
% until it returns true or timeoutSec elapses.
t0 = tic;
tf = false;
while toc(t0) < timeoutSec
    pause(0.02)
    if cond(), tf = true; return; end
end
end


function stopTwoAFCShot(RUNTIME, GUI)
% Stop the session timer (if still running) and close the GUI, mirroring
% smoke_test_two_afc's teardown.
try
    if isvalid(RUNTIME) && ~isempty(RUNTIME.TIMER) && isvalid(RUNTIME.TIMER) ...
            && strcmp(RUNTIME.TIMER.Running, 'on')
        stop(RUNTIME.TIMER);
    end
catch
end
try
    if isvalid(GUI), delete(GUI); end
catch
end
end


%% ------------------------------------------------------------------------
%  Behavior GUI Builder
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotBehaviorBuilder(C)
% Caption: mid-design over the detection example protocol, eight regions
% placed and the ninth just dropped into the free cell.
%
% The last region goes in through addRegion -- the same path a canvas drag
% takes -- because that is what leaves a region SELECTED, and an unselected
% canvas shows an empty inspector. Next Trial is the choice because its
% catalog entry has no options dialog: a type with one would block the run
% on a modal window nobody is there to dismiss.
specFile = builderShotSpec(C);
b = gui.BehaviorBuilder(specFile);
fig = findall(groot, 'Type','figure', '-and', 'Tag', gui.BehaviorBuilder.PREF_TAG);
fig = fig(1);   % the window handle is private to the class; find it by tag
fig.Position(3:4) = [1250 760];
drawnow
b.addRegion('NextTrial', [4 4], [4 4]);
drawnow
cleanupFcn = @() delete(b);
end


function [fig, cleanupFcn] = shotBehaviorBuilderGenerated(C)
% Caption: the class that design exports, running against a software-only
% runtime before any trials. Its whole job is to be compared with the
% canvas above it -- same panels, same cells.
specFile = builderShotSpec(C);
spec = gui.BehaviorBuilder.loadSpecFile(specFile);
spec.Regions(end+1) = struct('Id','R9', 'Type','NextTrial', 'Label','Next Trial', ...
    'Row',[4 4], 'Col',[4 4], 'PopOut',false, ...
    'Options',gui.BehaviorBuilder.defaultOptions('NextTrial'));
gui.BehaviorBuilder.writeCode(spec, specFile);
addpath(C.scratch);
rehash
clear(spec.ClassName)
G = feval(spec.ClassName, softwareRuntime(C));
fig = G.h_figure;
cleanupFcn = @() delete(G);
end


function specFile = builderShotSpec(C)
% The design both builder shots use: the detection example protocol laid
% out the way DetectionBehaviorGUI is, minus the one cell the shot fills in
% live. Written to scratch, never to the repository -- an .eblt in the tree
% would be a fixture nobody maintains.
spec = gui.BehaviorBuilder.specNew;
spec.ClassName  = 'ToneDetectionGUI';
spec.WindowName = 'Tone Detection';
spec.DefaultSize = [1180 700];
spec.Psych = struct('Type','Detection', 'Parameter','ToneLevel', ...
    'TargetTrialType','TrialType_0');
spec.ProtocolPath = C.protocol;
rt = softwareRuntime(C);
spec.ParameterSnapshot = gui.BehaviorBuilder.snapshotFromParameters( ...
    rt.all_parameters(includeTriggers=true));

btn = gui.BehaviorBuilder.defaultOptions('ButtonRow');
btn.Buttons = struct('Param', {'Reward'}, 'Text', {'Give Reward'});
btn.IncludeScreenCapture = true;
spec = builderShotRegion(spec, 'R1', 'ButtonRow', '', [1 1], [1 3], false, btn);

ctrl = gui.BehaviorBuilder.defaultOptions('ControlColumn');
ctrl.Controls = struct( ...
    'Param',      {'ToneFreq','ToneDur','ITI','RewardVol'}, ...
    'Type',       {'auto','auto','auto','auto'}, ...
    'autoCommit', {false, false, false, false}, ...
    'Text',       {'Tone Frequency (Hz)','Tone Duration (ms)','Intertrial Interval (ms)',''});
spec = builderShotRegion(spec, 'R2', 'ControlColumn', 'Trial Controls', ...
    [2 4], [1 1], false, ctrl);

mon = gui.BehaviorBuilder.defaultOptions('Monitor');
mon.Params = {'InTrial','RespCode','RT_ms'};
mon.PollPeriod = 0.5;
spec = builderShotRegion(spec, 'R3', 'Monitor', 'Monitor', [2 2], [2 2], true, mon);

sca = gui.BehaviorBuilder.defaultOptions('Scatter');
sca.YParameter = 'RT_ms';
sca.ColorParameter = 'RespCode';
spec = builderShotRegion(spec, 'R4', 'Scatter', 'Response Latency', ...
    [3 4], [2 2], false, sca);

spec = builderShotRegion(spec, 'R5', 'PsychPlot', 'Psychometric', [2 3], [3 3], false, ...
    gui.BehaviorBuilder.defaultOptions('PsychPlot'));
spec = builderShotRegion(spec, 'R6', 'History', 'Trials', [4 4], [3 3], false, ...
    gui.BehaviorBuilder.defaultOptions('History'));
spec = builderShotRegion(spec, 'R7', 'SessionClock', 'Clock', [1 1], [4 4], false, ...
    gui.BehaviorBuilder.defaultOptions('SessionClock'));
spec = builderShotRegion(spec, 'R8', 'Performance', 'Performance', [2 3], [4 4], false, ...
    gui.BehaviorBuilder.defaultOptions('Performance'));

specFile = fullfile(C.scratch, 'ToneDetection.eblt');
gui.BehaviorBuilder.saveSpecFile(spec, specFile);
end


function spec = builderShotRegion(spec, id, type, label, rowSpan, colSpan, popOut, options)
spec.Regions(end+1) = struct('Id',id, 'Type',type, 'Label',label, ...
    'Row',rowSpan, 'Col',colSpan, 'PopOut',popOut, 'Options',options);
end


%% ------------------------------------------------------------------------
%  Session window and diagnostics
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotRunExpt(C)
% Caption: two subjects loaded from a saved .ecfg, Run and Preview enabled.
cfgFile = writeConfig(C, [1 2]);
RE = epsych.RunExpt(cfgFile);
drawnow
fig = RE.H.figure1;
fig.Position(3:4) = [790 316];
cleanupFcn = @() closeRunExpt(RE);
end


function [fig, cleanupFcn] = shotSubjectManager(C)
% Caption: a project selected on the left with its members checked, one of them
% behind on its protocol so the stale-version banner and the orange Version
% cell are both in the shot.
%
% The roster lives in C.scratch and the RosterFile preference is pointed at it
% for the duration. That preference is a real rig setting -- snapshotPrefs
% covers ep_RunExpt_Subjects, and the cleanup clears it rather than leaving a
% tempdir path behind for a later run to faithfully restore.
rosterFile = fullfile(C.scratch, 'wiki_shot_subjects.esub');
if isfile(rosterFile), delete(rosterFile); end
epsych.SubjectRoster.setConfiguredFile(rosterFile);

% The project's protocol is a scratch copy, because making a row read as
% "behind" means saving the .eprot again after the version was recorded --
% exactly what an operator editing a protocol between sessions does. Doing
% that to the example protocol in the repository would dirty the working tree.
protoFile = fullfile(C.scratch, 'ToneDetection.eprot');
copyfile(C.protocol, protoFile);
P = epsych.Protocol.load(protoFile);
P.save(protoFile);

R = epsych.SubjectRoster(rosterFile);
pid = R.addProject('Tone Detection', ...
    Investigator = 'D. Stolzberg', ...
    IACUCProtocol = 'R-2026-14', ...
    DefaultProtocol = protoFile, ...
    DefaultDataPath = 'D:\data\tone_detection');
R.addProject('Gap Detection', DefaultProtocol = protoFile);

names = {'M001','M002','M003','M004'};
ids = cell(1, numel(names));
for k = 1:numel(names)
    ids{k} = R.addSubject(struct('Name', names{k}, 'Sex', 'Male', ...
        'Species', 'Gerbil', 'Weight', 58 + 2*k));
    R.assign(ids{k}, pid);
end

% Three record the version now in the file; the fourth records nothing, which
% is the other state the Version column has ("not recorded", greyed).
for k = 1:3
    R.rememberProtocol(ids{k}, pid, protoFile);
end

% Now the protocol is saved again behind the roster's back. Those three are
% suddenly a version behind, which opens the banner over the table -- the part
% of this window most worth showing, and the thing nobody thinks to look for.
P.save(protoFile);

cfgFile = writeConfig(C, 1);
RE = epsych.RunExpt(cfgFile);
drawnow
mgr = gui.SubjectManager(RE);
drawnow

% Open on the project rather than <All Subjects>: the summary, the banner, and
% the version check are all per project, so the default view shows none of them.
mgr.H.projectList.Value = pid;
mgr.refresh();
tickRow(mgr, 1);
tickRow(mgr, 2);
drawnow

fig = mgr.H.figure;
fig.Position(3:4) = [1180 640];
cleanupFcn = @() closeSubjectManager(RE, fig);
end


function tickRow(mgr, row)
% Tick a checkbox the way the table's own callback would -- setting Data alone
% updates the cell but not the count label or the enable states.
if size(mgr.H.table.Data,1) < row, return, end
mgr.H.table.Data{row,1} = true;
mgr.H.table.CellEditCallback([], struct( ...
    'Indices', [row 1], 'NewData', true, 'PreviousData', false));
end


function closeSubjectManager(RE, fig)
if isvalid(fig), delete(fig); end
% Never leave the rig pointed at a roster under tempdir.
epsych.SubjectRoster.setConfiguredFile('');
closeRunExpt(RE);
end


function [fig, cleanupFcn] = shotSelfTest(C)
% Caption: a real pre-flight result whose red rows come from a subject sitting
% in box 2 while the protocol only defines the box-1 trigger parameters.
cfgFile = writeConfig(C, [1 2]);
RE = epsych.RunExpt(cfgFile);
drawnow
ST = gui.SelfTest(RE);
drawnow
% runSelected already selects the first row needing attention and expands its
% detail pane, which is the point of the shot.
ST.runSelected([epsych.SelfTest.catalog().id]);
drawnow
fig = ST.H.figure;
fig.Position(3:4) = [1040 620];
cleanupFcn = @() closeSelfTest(RE, fig);
end


function closeSelfTest(RE, fig)
if isvalid(fig), delete(fig); end
closeRunExpt(RE);
end


function cfgFile = writeConfig(C, boxIDs)
% A .ecfg is save(fn,'config','funcs','meta'): config is a struct array of
% SUBJECT/PROTOCOL/RUNTIME/protocol_fn, and funcs nests the timer callbacks
% under TIMERfcn. Both shapes fail inside LoadConfig rather than at save time.
P = epsych.Protocol.load(C.protocol);
if P.needsCompile, P.compile(); end

names = {'M001','M002','M003'};
config = struct('SUBJECT', {}, 'PROTOCOL', {}, 'RUNTIME', {}, 'protocol_fn', {});
for k = 1:numel(boxIDs)
    S = epsych.DefaultSubject(struct('Name', names{k}, 'Species', 'Mouse', ...
        'Sex', 'Unknown', 'BoxID', boxIDs(k)));
    config(k).SUBJECT     = S.toStruct();
    config(k).PROTOCOL    = P.toStruct();
    config(k).RUNTIME     = [];
    config(k).protocol_fn = C.protocol;
end

funcs = struct();
funcs.TIMERfcn = struct('Start', 'ep_TimerFcn_Start', 'RunTime', 'ep_TimerFcn_RunTime', ...
    'Stop', 'ep_TimerFcn_Stop', 'Error', 'ep_TimerFcn_Error');
funcs.SavingFcn    = 'ep_SaveDataFcn';
funcs.BehaviorGUI       = 'ep_GenericGUI';
funcs.AddSubjectFcn = 'epsych.DefaultSubject.open';
funcs.TimerPeriod  = 0.05;

meta = EPsychInfo().meta;   %#ok<NASGU> saved for provenance, like a real config
cfgFile = fullfile(C.scratch, 'DetectionExample.ecfg');  % the name lands in the status bar
save(cfgFile, 'config', 'funcs', 'meta', '-mat');
end


function closeRunExpt(RE)
if ~isvalid(RE), return; end
RE.IsClosing = true;
if isfield(RE.H, 'figure1') && isvalid(RE.H.figure1)
    delete(RE.H.figure1);
end
delete(RE);
end


%% ------------------------------------------------------------------------
%  stimgen windows
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotStimPlayer(~)
% Caption: the stimulus bank on the left, the property editor generated from
% the selected stimulus class on the right, the waveform above.
closeByName('StimPlayer');
SP = stimgen.StimPlayer;
drawnow
fig = figureByName('StimPlayer');

% add_stim reads the stimulus-type dropdown, and the handle struct is
% private, so drive the widget the operator would use.
dd = findall(fig, 'Type', 'uidropdown');
td = dd(arrayfun(@(d) any(strcmp(d.Items, 'Tone')), dd));
for t = ["Tone","Noise","AMnoise"]
    td(1).Value = char(t);
    SP.add_stim();
end
drawnow
cleanupFcn = @() delete(SP);
end


function [fig, cleanupFcn] = shotCalibrationGui(~)
% Caption: opened with epsych.calibrate and no protocol, so every measurement
% button is disabled and the sample rate reads "No adapter".
closeByName('Stim Calibration');
G = epsych.calibrate;
drawnow
fig = figureByName('Stim Calibration');
cleanupFcn = @() delete(G);
end


%% ------------------------------------------------------------------------
%  Teensy trial designer
% -------------------------------------------------------------------------
function [fig, cleanupFcn] = shotTeensyChannels(C)
[TD, fig, cleanupFcn] = openTeensyDesigner(C);
TD.TabGroup.SelectedTab = TD.TabGroup.Children(1);   % Channels
end


function [fig, cleanupFcn] = shotTeensyStates(C)
[TD, fig, cleanupFcn] = openTeensyDesigner(C);
TD.TabGroup.SelectedTab = TD.TabGroup.Children(2);   % States
end


function [fig, cleanupFcn] = shotTeensyTestBench(C)
[TD, fig, cleanupFcn] = openTeensyDesigner(C);
TD.TabGroup.SelectedTab = TD.TabGroup.Children(4);   % Test Bench
end


function [TD, fig, cleanupFcn] = openTeensyDesigner(~)
% All three Teensy shots are the Go/No-Go template, one tab each.
TD = teensy.TrialDesigner(teensy.Templates.get('GoNoGoDetection'));
drawnow
fig = TD.Figure;
fig.Position(3:4) = [1200 720];
cleanupFcn = @() delete(TD);
end


function fig = figureByName(name)
% The stimgen windows keep their figure handle private; find it by title.
fig = findall(groot, 'Type', 'figure', '-and', 'Name', name);
if isempty(fig)
    error('generate_wiki_screenshots:NoFigure', 'No open figure named "%s".', name);
end
fig = fig(1);
end


function closeByName(name)
delete(findall(groot, 'Type', 'figure', '-and', 'Name', name));
end


%% ------------------------------------------------------------------------
%  Shared fixtures
% -------------------------------------------------------------------------
function rt = softwareRuntime(C)
% The example protocol's hw.Software interface, connected, no trials.
P = epsych.Protocol.load(C.protocol);
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
rt.Interfaces = P.Interfaces;

% add_parameter fills the design-time Values list, not the live Value; trial
% dispatch normally does that. Without it every widget would read 0.
for p = rt.all_parameters(includeTriggers=true)
    v = p.Values;
    if iscell(v), v = v{1}; end
    if isempty(v), continue; end
    setReadValue(p, v(1));
end
end


function S = detectionSession(C)
S.RUNTIME = run_detection_session(NumTrials=150, ShowGUI=false, ...
    DataPath=C.scratch, Seed=7);
S.RUNTIME.TRIALS(1).TrialIndex = numel(S.RUNTIME.TRIALS(1).DATA);
S.Level = S.RUNTIME.find_parameter('ToneLevel');
S.Psych = psychophysics.Detection(S.RUNTIME, S.Level, epsych.BitMask.TrialType_0);
S.DATA  = S.RUNTIME.TRIALS(1).DATA;
S.TrialsEvent = epsych.TrialsData(S.RUNTIME.TRIALS(1));
S.Psych.update_data([], S.TrialsEvent);
end


%% ------------------------------------------------------------------------
%  Utilities
% -------------------------------------------------------------------------
function setReadValue(p, v)
if isempty(p), return; end
ac = p.Access;
p.Access = 'Any';
p.Value = v;
p.Access = ac;
end


function closeByTag(tag)
delete(findall(groot, 'Type', 'figure', '-and', 'Tag', tag));
end


function s = topFrame(ME)
if isempty(ME.stack)
    s = 'no stack';
else
    s = sprintf('%s:%d', ME.stack(1).name, ME.stack(1).line);
end
end


function P = snapshotPrefs()
groups = {'ProtocolDesigner', 'epsych2_gui_History', 'epsych2_gui_ParameterScatter', ...
    'epsych2_gui_Parameter_Monitor', 'epsych2_gui_PhaseSelector', 'StaircaseTraining', ...
    'ExampleBehaviorGUI', 'DetectionBehaviorGUI', 'TwoAFCBehaviorGUI', ...
    'ep_RunExpt_Subjects', 'epsych2_gui_SubjectManager', ...
    'gui_BehaviorBuilder', 'ToneDetectionGUI'};
P = struct('group', groups, 'value', []);
for k = 1:numel(groups)
    if ispref(groups{k}), P(k).value = getpref(groups{k}); end
end
end


function restorePrefs(P)
for k = 1:numel(P)
    if ispref(P(k).group), rmpref(P(k).group); end
    if ~isempty(P(k).value)
        f = fieldnames(P(k).value);
        for i = 1:numel(f)
            setpref(P(k).group, f{i}, P(k).value.(f{i}));
        end
    end
end
closeByTag('wikiShot');
end
