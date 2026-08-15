function generate_component_screenshots(options)
% generate_component_screenshots(Name=Value, ...)
% Capture each reusable obj/+gui component on its own, for the wiki's
% "Box GUI Components" gallery. Every shot is one component in a bare
% uifigure sized to it, so the image shows the component and nothing else.
%
% Headless: figures are built Visible='off' and exportapp captures them
% anyway, so this never steals focus or disturbs a live session. Every
% preference the components write is snapshotted and restored on exit.
%
% Options:
%   OutputDir - Folder for the .png files (default: ../epsych2.wiki/images/components)
%   Only      - Capture just these shot names (default: all)
%   NumTrials - Simulated trials backing the data-driven components (default 150)
%   Seed      - rng seed for the simulated session (default 7)
%
%   matlab -batch "run('tmp/generate_component_screenshots.m')"
%   generate_component_screenshots(Only=["History","PsychPlot"])

arguments
    options.OutputDir (1,:) char = ''
    options.Only (1,:) string = string.empty(1,0)
    options.NumTrials (1,1) double {mustBeInteger,mustBePositive} = 150
    options.Seed (1,1) double = 7
end

here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(here);
run(fullfile(repoRoot, 'epsych_startup.m'));
addpath(fullfile(repoRoot, 'examples', 'detection_task'));

if isempty(options.OutputDir)
    options.OutputDir = fullfile(fileparts(repoRoot), 'epsych2.wiki', 'images', 'components');
end
if ~isfolder(options.OutputDir), mkdir(options.OutputDir); end

prefs = snapshotPrefs();
restore = onCleanup(@() restorePrefs(prefs));

S = buildSession(options);
closeSession = onCleanup(@() delete(S.Psych));

shots = { ...
    'Parameter_Control',            @shotParameterControl; ...
    'Parameter_Update',             @shotParameterUpdate; ...
    'Parameter_Monitor_Table',      @shotMonitorTable; ...
    'Parameter_Monitor_Graphical',  @shotMonitorGraphical; ...
    'NextTrial',                    @shotNextTrial; ...
    'SessionClock',                 @shotSessionClock; ...
    'ElapsedTrialTimer',            @shotElapsedTrialTimer; ...
    'ModeIndicator',                @shotModeIndicator; ...
    'StatusBar',                    @shotStatusBar; ...
    'History',                      @shotHistory; ...
    'SessionPerformance',           @shotSessionPerformance; ...
    'ParameterScatter',             @shotParameterScatter; ...
    'PsychPlot',                    @shotPsychPlot; ...
    'Performance',                  @shotPerformance; ...
    'SlidingWindowPerformancePlot', @shotSlidingWindow; ...
    'Staircase_Plot',               @shotStaircasePlot; ...
    'PhaseSelector',                @shotPhaseSelector; ...
    'StaircaseTraining',            @shotStaircaseTraining; ...
    'SyringePump',                  @shotSyringePump; ...
    'ParameterDebugger',            @shotParameterDebugger; ...
    'FilenameValidator',            @shotFilenameValidator; ...
    'BoxGUI_Helpers',               @shotBoxGUIHelpers; ...
    };

names = string(shots(:,1));
if ~isempty(options.Only)
    keep = ismember(names, options.Only);
    if ~any(keep)
        error('generate_component_screenshots:UnknownShot', ...
            'No shot matches %s. Available: %s', strjoin(options.Only,', '), strjoin(names,', '));
    end
    shots = shots(keep,:);
end

nFail = 0;
for k = 1:size(shots,1)
    name = shots{k,1};
    fcn  = shots{k,2};
    fig  = [];
    try
        fig = fcn(S);
        drawnow; pause(0.25); drawnow   % let timers and listeners settle
        outFile = fullfile(options.OutputDir, [name '.png']);
        exportapp(fig, outFile);
        d = dir(outFile);
        fprintf('  %-30s %6.1f KB  %s\n', name, d.bytes/1024, outFile);
    catch ME
        nFail = nFail + 1;
        fprintf(2, '  %-30s FAILED: %s (%s)\n', name, ME.message, topFrame(ME));
    end
    closeFigure(fig);
end

fprintf('\n%d of %d shots written to %s\n', size(shots,1)-nFail, size(shots,1), options.OutputDir);
end


%% ------------------------------------------------------------------------
%  Shared session
% -------------------------------------------------------------------------
function S = buildSession(options)
% A finished 150-trial detection session, the data source for every
% component that displays trials. Data lands in the temp folder, not the repo.
dataPath = fullfile(tempdir, 'epsych_wiki_shots');
if ~isfolder(dataPath), mkdir(dataPath); end

fprintf('Simulating %d trials for the data-driven components...\n', options.NumTrials);
S.RUNTIME = run_detection_session(NumTrials=options.NumTrials, ...
    ShowGUI=false, DataPath=dataPath, Seed=options.Seed);

% The trial loop leaves TrialIndex one past the last completed trial (it is
% the index the *next* trial would take). Components that index trial arrays
% by it — gui.SlidingWindowPerformancePlot — read off the end otherwise.
S.RUNTIME.TRIALS(1).TrialIndex = numel(S.RUNTIME.TRIALS(1).DATA);

S.Level = S.RUNTIME.find_parameter('ToneLevel');
S.Psych = psychophysics.Detection(S.RUNTIME, S.Level, epsych.BitMask.TrialType_0);
S.DATA  = S.RUNTIME.TRIALS(1).DATA;
S.TrialsEvent = epsych.TrialsData(S.RUNTIME.TRIALS(1));
S.Psych.update_data([], S.TrialsEvent);   % seed the analysis with the whole session
end


function pushData(S)
% Re-broadcast the finished session so components built after the run fill in.
S.RUNTIME.EVENTS.notify('NewData', S.TrialsEvent);
end


function pushTrial(S)
S.RUNTIME.EVENTS.notify('NewTrial', S.TrialsEvent);
end


function replayTrials(S)
% Re-broadcast the session one trial at a time, for components that build
% their display from the event sequence rather than from the final DATA.
T = S.RUNTIME.TRIALS(1);
for k = 1:numel(T.DATA)
    Tk = T;
    Tk.DATA = T.DATA(1:k);
    Tk.TrialIndex = k;
    S.RUNTIME.EVENTS.notify('NewData', epsych.TrialsData(Tk));
end
drawnow
end


%% ------------------------------------------------------------------------
%  Parameter binding widgets
% -------------------------------------------------------------------------
function fig = shotParameterControl(S)
fig = shotFigure([440 220]);
g = uigridlayout(fig, [5 1]);
g.RowHeight = repmat({32}, 1, 5);
g.Padding = [10 10 10 10];

C = gui.Parameter_Control(g, S.RUNTIME.find_parameter('ToneFreq'), ...
    Text='Tone Frequency (Hz)');
gui.Parameter_Control(g, S.RUNTIME.find_parameter('ToneDur'), Text='Tone Duration (ms)');
gui.Parameter_Control(g, S.RUNTIME.find_parameter('ITI'), Type='range', ...
    Text='Intertrial Interval (ms)');
gui.Parameter_Control(g, S.RUNTIME.find_parameter('ITI'), BoundProperty='isRandom', ...
    Type='checkbox', Text='Randomize ITI');
gui.Parameter_Control(g, S.RUNTIME.find_parameter('Reward'), Type='momentary', ...
    Text='Deliver Reward');

% One staged edit, so the "edited but not committed" highlight is visible.
C.Value = 8000;
end


function fig = shotParameterUpdate(S)
fig = shotFigure([360 190]);
g = uigridlayout(fig, [3 1]);
g.RowHeight = {34, 34, 40};
g.Padding = [10 10 10 10];

c1 = gui.Parameter_Control(g, S.RUNTIME.find_parameter('ToneFreq'), Text='Tone Frequency (Hz)');
c2 = gui.Parameter_Control(g, S.RUNTIME.find_parameter('RewardVol'), Text='Reward Volume (uL)');

U = gui.Parameter_Update(S.RUNTIME, g);
U.watchedHandles = [c1 c2];
c1.Value = 8000;   % stage an edit: the button turns green and says so
end


function fig = shotMonitorTable(S)
fig = shotFigure([510 190]);
P = [S.RUNTIME.find_parameter('ToneLevel'), S.RUNTIME.find_parameter('ToneFreq'), ...
    S.RUNTIME.find_parameter('ToneDur'), S.RUNTIME.find_parameter('RespCode'), ...
    S.RUNTIME.find_parameter('InTrial')];
gui.Parameter_Monitor(fig, P, type='table', pollPeriod=0.5, ...
    Columns=["Type","UpdateEveryTrial"], PreferenceTag="wikiShotMonitorTable");
end


function fig = shotMonitorGraphical(S)
fig = shotFigure([300 125]);
P = [S.RUNTIME.find_parameter('InTrial'), S.RUNTIME.find_parameter('ToneLevel'), ...
    S.RUNTIME.find_parameter('ToneFreq'), S.RUNTIME.find_parameter('RespCode')];
setReadValue(S.RUNTIME.find_parameter('InTrial'), true);
gui.Parameter_Monitor(fig, P, type='graphical', pollPeriod=0.5, ...
    PreferenceTag="wikiShotMonitorGraphical");
end


%% ------------------------------------------------------------------------
%  Trial and session state
% -------------------------------------------------------------------------
function fig = shotNextTrial(S)
fig = shotFigure([330 180]);
gui.NextTrial(S.RUNTIME, fig, FontSize=14, PreferenceTag='wikiShotNextTrial', ...
    Fields=["TrialType","ToneLevel","ToneFreq","ITI"]);
pushTrial(S);
end


function fig = shotSessionClock(S)
% The clock lays itself out in a grid; given a bare figure its panel takes a
% default position and the lines land off-screen. Hand it a layout cell.
fig = shotFigure([300 130]);
g = uigridlayout(fig, [1 1]);
g.Padding = [4 4 4 4];
c = gui.SessionClock(g, PreferenceTag='wikiShotSessionClock', FontSize=13);
c.attachRuntime(S.RUNTIME);
c.start();
pushTrial(S);      % without a trial the two trial lines read "--"
pause(2.2)
c.refresh();
end


function fig = shotElapsedTrialTimer(S)
fig = shotFigure([300 70]);
g = uigridlayout(fig, [1 1]);
t = gui.ElapsedTrialTimer(g, FontSize=18, Prefix='Last trial: ', FontWeight='bold');
t.attachRuntime(S.RUNTIME);
t.start();
pause(3.2)   % let the counter run, so the shot shows a live clock not 00:00:00
end


function fig = shotModeIndicator(~)
fig = shotFigure([170 120]);
ind = gui.ModeIndicator(fig, FontSize=13);
ind.setState(hw.DeviceState.Record);
end


function fig = shotStatusBar(~)
fig = shotFigure([560 80]);
sb = gui.StatusBar(fig, Position=[15 22 530 36]);
sb.setStatus('Protocol compiled: 6 conditions.', 'Press Run to start the session.');
end


%% ------------------------------------------------------------------------
%  Online analysis
% -------------------------------------------------------------------------
function fig = shotHistory(S)
% gui.History reads responseBits, so it wants a psychophysics.Psych
% subclass; psychophysics.Detection is not one. A Staircase in offline mode
% is the same object a real box GUI hands it.
fig = shotFigure([540 300]);
sc = psychophysics.Staircase(S.DATA, S.Level);
H = gui.History(sc, fig, PreferenceTag='wikiShotHistory');
% green hit, red miss, blue correct reject, orange false alarm, yellow abort
H.BitColors               = ["#c8ffd9","#ffcdcd","#b3e1ff","#ffeacf","#faffcc"];
H.ParametersOfInterest    = {'ToneLevel','TrialType'};
H.ParameterColumnFormats  = {'%g','%d'};
H.update();
end


function fig = shotStaircasePlot(S)
fig = shotFigure([580 320]);
ax = axes(uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 1]));
psychophysics.Staircase(S.DATA, S.Level, Plot=true, PlotAxes=ax);
end


function fig = shotSessionPerformance(S)
fig = shotFigure([340 175]);
p = uipanel(fig, 'Title', 'Session Performance', 'Units', 'normalized', 'Position', [0 0 1 1]);
gui.SessionPerformance(S.DATA, p, PreferenceTag='wikiShotSessionPerformance');
end


function fig = shotParameterScatter(S)
fig = shotFigure([650 380]);
gui.ParameterScatter(S.DATA, fig, PreferenceTag='wikiShotScatter', ...
    XParameter='TrialIndex', YParameter='ToneLevel', ColorParameter='Response');
end


function fig = shotPsychPlot(S)
fig = shotFigure([520 360]);
ax = axes(uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 1]));
gui.PsychPlot(S.Psych, ax);
pushData(S);
end


function fig = shotPerformance(S)
fig = shotFigure([540 185]);
P = gui.Performance(S.Psych, fig);
P.ParametersOfInterest = {'ToneLevel'};
pushData(S);
end


function fig = shotSlidingWindow(S)
fig = shotFigure([580 320]);
ax = axes(uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 1]));
W = gui.SlidingWindowPerformancePlot(S.Psych, ax);
W.windowSize = 30;
replayTrials(S);   % this one plots per-trial history, so it needs the trials one at a time
end


%% ------------------------------------------------------------------------
%  Session control
% -------------------------------------------------------------------------
function fig = shotPhaseSelector(S)
% A throwaway phase folder, so the dropdown has something to show.
phaseDir = fullfile(tempdir, 'epsych_wiki_phases');
if ~isfolder(phaseDir), mkdir(phaseDir); end
src = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'examples', 'detection_task', ...
    'DetectionExample.eprot');
for nm = ["Shaping","Training_Easy","Training_Hard","Testing"]
    dst = fullfile(phaseDir, nm + ".eprot");
    if ~isfile(dst), copyfile(src, dst); end
end

fig = shotFigure([420 145]);
ps = gui.PhaseSelector(S.RUNTIME, phaseDir);
ps.PhasePath = phaseDir;     % outrank any saved directory preference
ps.createGUI(fig);
ps.h_PhaseSelect.Value = ps.Names(3);
ps.onPhaseSelectionChanged(ps.h_PhaseSelect);
end


function fig = shotStaircaseTraining(S)
fig = shotFigure([560 330]);
gui.StaircaseTraining(S.RUNTIME.find_parameter('ToneLevel'), Parent=fig, ...
    MinValue=10, MaxValue=70, StepUp=2, StepDown=5, ...
    StepUpResponse="Hit", StepDownResponse="Miss");
end


function fig = shotSyringePump(~)
% Over the in-process pump mock, so the panel shows a connected link and a
% real dispensed volume rather than the disconnected state.
mock = NE1000_Mock(SyringeDiameter=21.59);
mock.SimInfused = 0.836;              % mL on the wire; the panel displays uL

fig = shotFigure([360 260]);
p = gui.SyringePump(mock, fig, PreferenceTag='wikiShotSyringePump');
p.refresh();
fig.UserData = {p, mock};             % closeFigure tears both down
end


function fig = shotParameterDebugger(S)
% A whole window rather than a component, so this returns the debugger's own
% figure. Pointed at the simulated session's protocol and swept once, so the
% table shows real parameters with real values and the read colouring the
% window is about.
D = gui.ParameterDebugger(S.RUNTIME, Visible=false);
fig = D.H.figure;
fig.Position = [200 200 1180 520];
D.readAll();
end


function fig = shotFilenameValidator(S)
fig = shotFigure([540 72]);
g = uigridlayout(fig, [1 1]);
g.Padding = [8 8 8 8];
gui.FilenameValidator(S.RUNTIME, g, 'ExampleSubject_260813_detection');
end


function fig = shotBoxGUIHelpers(S)
% The helpers gui.BoxGUI itself provides: a row of trigger buttons, a titled
% control column ending in an update button, and a polled monitor.
G = WikiHelperBoxGUI(S.RUNTIME);
fig = G.h_figure;
end


%% ------------------------------------------------------------------------
%  Utilities
% -------------------------------------------------------------------------
function fig = shotFigure(sz)
fig = uifigure('Visible', 'off', 'Position', [200 200 sz(1) sz(2)], ...
    'Tag', 'wikiComponentShot', 'Name', '');
end


function closeFigure(fig)
% A gui.BoxGUI parks itself in the figure's UserData, and a shot may park a
% cell of objects it owns (panel, mock interface) there; deleting the figure
% alone would leave those objects, their listeners, and their timers behind.
if ~isempty(fig) && isgraphics(fig)
    owner = fig.UserData;
    delete(fig);
    if ~iscell(owner), owner = {owner}; end
    for k = numel(owner):-1:1
        if isa(owner{k}, 'handle') && isvalid(owner{k}), delete(owner{k}); end
    end
end
drawnow
end


function setReadValue(p, v)
% Rig-side write to a read-back parameter (Access='Read' blocks set.Value).
if isempty(p), return; end
ac = p.Access;
p.Access = 'Any';
p.Value = v;
p.Access = ac;
end


function s = topFrame(ME)
if isempty(ME.stack)
    s = 'no stack';
else
    s = sprintf('%s:%d', ME.stack(1).name, ME.stack(1).line);
end
end


function P = snapshotPrefs()
% Every preference group the captured components write to, so a shot run
% cannot change what the developer sees in their own session.
groups = {'epsych2_gui_History', 'epsych2_gui_NextTrial', ...
    'epsych2_gui_ParameterScatter', 'epsych2_gui_Parameter_Monitor', ...
    'epsych2_gui_SessionPerformance', 'epsych2_gui_PhaseSelector', ...
    'epsych2_gui_SyringePump', 'epsych2_gui_ParameterDebugger', ...
    'StaircaseTraining', 'wikiShotSessionClock'};
P = struct('group', groups, 'value', []);
for k = 1:numel(groups)
    if ispref(groups{k})
        P(k).value = getpref(groups{k});
    end
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
delete(findall(groot, 'Type', 'figure', '-and', 'Tag', 'wikiComponentShot'));
end
