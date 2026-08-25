function generate_component_screenshots(options)
% generate_component_screenshots(Name=Value, ...)
% Capture each reusable obj/+gui component on its own, for the wiki's
% "Behavior GUI Components" gallery. Every shot is one component in a bare
% uifigure sized to it, so the image shows the component and nothing else.
%
% The session behind the shots is a REAL one, reopened through
% epsych.ReviewSession: real parameters with real names, units and limits, and
% real trial outcomes. Two files, because no single session exercises
% everything:
%
%   DataFile      - an appetitive AM-detection session (cl_AppetitiveStimDetect).
%                   It carries a full protocol snapshot, so the parameter
%                   controls, the monitors and the debugger are the rig's own.
%                   Source for every shot except the three below.
%   PsychDataFile - a session run at several AM depths, for the three
%                   components that plot a function against stimulus level
%                   (PsychPlot, Performance, SlidingWindowPerformancePlot).
%                   DataFile is a stimulus-delay training session with the
%                   depth pinned, so those three would draw a single point.
%
% Headless: figures are built Visible='off' and exportapp captures them
% anyway, so this never steals focus or disturbs a live session. Every
% preference the components write is snapshotted and restored on exit.
%
% Options:
%   OutputDir     - Folder for the .png files (default: ../epsych2.wiki/images/components)
%   DataFile      - Session .mat behind most of the shots
%   PsychDataFile - Multi-level session behind the psychometric shots
%   PhaseDir      - Folder of .eprot phase files for the PhaseSelector shot
%   Only          - Capture just these shot names (default: all)
%
%   matlab -batch "run('tmp/generate_component_screenshots.m')"
%   generate_component_screenshots(Only=["History","PsychPlot"])

arguments
    options.OutputDir (1,:) char = ''
    options.DataFile (1,:) char = 'D:\epsych_files\Data\SUBJ-ID-1255\SUBJ-ID-1255_260821T092900.mat'
    options.PsychDataFile (1,:) char = 'D:\epsych_files\Data\SUBJ-ID-1106\SUBJ-ID-1106_14-Jan-2026.mat'
    options.PhaseDir (1,:) char = 'D:\epsych_files\Protocols\Phases'
    options.Only (1,:) string = string.empty(1,0)
end

here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(here);
run(fullfile(repoRoot, 'epsych_startup.m'));
addpath(here);   % BatchProbeInterface and NE1000_Mock, the two mocked backends

if isempty(options.OutputDir)
    options.OutputDir = fullfile(fileparts(repoRoot), 'epsych2.wiki', 'images', 'components');
end
if ~isfolder(options.OutputDir), mkdir(options.OutputDir); end

prefs = snapshotPrefs();
restore = onCleanup(@() restorePrefs(prefs));

S = buildSession(options);
closeSession = onCleanup(@() closeSessions(S));

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
    'OnlinePlot',                   @shotOnlinePlot; ...
    'BufferPlot',                   @shotBufferPlot; ...
    'SessionGate',                  @shotSessionGate; ...
    'RegenerateTrial',              @shotRegenerateTrial; ...
    'KeyBindings',                  @shotKeyBindings; ...
    'StaircaseTraining',            @shotStaircaseTraining; ...
    'SyringePump',                  @shotSyringePump; ...
    'Notes',                        @shotNotes; ...
    'ParameterDebugger',            @shotParameterDebugger; ...
    'FilenameValidator',            @shotFilenameValidator; ...
    'ComponentToolbar',             @shotComponentToolbar; ...
    'ScreenCapture',                @shotScreenCapture; ...
    'BehaviorGUI_Helpers',          @shotBehaviorGUIHelpers; ...
    'PhaseSelector',                @shotPhaseSelector; ...
    };
% PhaseSelector is captured last on purpose: selecting a phase loads its
% parameter values into the runtime, which would change what every shot after
% it displays.

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
% The two finished sessions behind the data-driven components, reopened the
% way epsych.ReviewSession reopens any saved file: a real epsych.Runtime, a
% real epsych.EventHub, hw.Replay backends answering every parameter read
% from the record.

S.Options = options;

fprintf('Session:   %s\n', options.DataFile);
S.Review  = epsych.ReviewSession(options.DataFile, Show=false);
S.RUNTIME = S.Review.RUNTIME;
S.DATA    = S.Review.Data;
fprintf('  %d trials, %d parameters\n', numel(S.DATA), ...
    numel(S.RUNTIME.all_parameters(includeInvisible=true, includeTriggers=true)));

% The gallery photographs the components as they look DURING a session, not
% after it: gui.components.Parameter_Control greys itself out on an idle interface, so
% every control in every shot would be dead. The review left the backends in
% Standby; Record is the state a running box is in.
for p = S.Review.Interfaces(:).'
    p.mode = hw.DeviceState.Record;
end

% ReviewMode is what suppressed the one-shot dispatch while the review seated
% itself at the last trial. That has happened; from here nothing assigns
% RUNTIME.TRIALS again (the re-broadcast helpers below notify the hub
% directly), so clearing it is inert -- and it is what lets gui.components.Notes accept
% typing and gui.components.SessionGate arm, neither of which a review permits.
S.RUNTIME.ReviewMode = false;

S.TrialsEvent = epsych.TrialsData(S.RUNTIME.TRIALS(1));

% --- the multi-level session, for the three level-vs-performance plots ----
fprintf('Psych:     %s\n', options.PsychDataFile);
S.PsychReview  = epsych.ReviewSession(options.PsychDataFile, Show=false);
S.PsychRUNTIME = S.PsychReview.RUNTIME;

% This file writes its outcomes under the older name 'ResponseCode';
% psychophysics.Detection.responseCodes resolves that pair, so nothing has to
% be renamed here.
T = S.PsychRUNTIME.TRIALS(1);

% The file records no subject, so the review named it after the file itself and
% every plot title carries the timestamp -- with the underscore read as a TeX
% subscript. The animal's own folder is the identity that file has.
[~, T.Subject.Name] = fileparts(fileparts(options.PsychDataFile));

S.PsychRUNTIME.TRIALS = T;      % still in ReviewMode, so this does not dispatch
S.PsychRUNTIME.ReviewMode = false;
S.PsychDATA = T.DATA;

% That file predates epsych.SessionSnapshot, so it carries no protocol and the
% review has no parameters. psychophysics.Detection needs a hw.Parameter to
% name the analyzed DATA field and label the axis; an hw.Software one is the
% same object a live session would hand it.
S.PsychIface = hw.Software();
S.Level = S.PsychIface.Module.add_parameter('Depth', ...
    median(unique([S.PsychDATA([S.PsychDATA.TrialType] == 0).Depth])), ...
    Description="Amplitude modulation depth", Format='%.3g');

% Stimulus trials only: without it the catch trials contribute a level of their
% own at the bottom of the axis.
S.Psych = psychophysics.Detection(S.PsychRUNTIME, S.Level, epsych.BitMask.TrialType_0);
S.PsychTrialsEvent = epsych.TrialsData(S.PsychRUNTIME.TRIALS(1));
S.Psych.update_data([], S.PsychTrialsEvent);   % seed with the whole session
fprintf('  %d trials, %d depths\n', numel(S.PsychDATA), numel(S.Psych.uniqueValues));
end


function closeSessions(S)
delete(S.Psych);
delete(S.Review);
delete(S.PsychReview);
delete(S.PsychIface);
end


function pushData(S)
% Re-broadcast the finished session so components built after the run fill in.
% Deliberately a notify rather than S.Review.seek(): seek assigns
% RUNTIME.TRIALS, and with ReviewMode cleared that dispatches a trial -- which
% would write over the very values being photographed.
S.RUNTIME.EVENTS.notify('NewData', S.TrialsEvent);
end


function pushTrial(S)
S.RUNTIME.EVENTS.notify('NewTrial', S.TrialsEvent);
end


function replayTrials(S)
% Re-broadcast the multi-level session one trial at a time, for components
% that build their display from the event sequence rather than from the final
% DATA.
T = S.PsychRUNTIME.TRIALS(1);
for k = 1:numel(T.DATA)
    Tk = T;
    Tk.DATA = T.DATA(1:k);
    Tk.TrialIndex = k;
    S.PsychRUNTIME.EVENTS.notify('NewData', epsych.TrialsData(Tk));
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

C = gui.components.Parameter_Control(g, S.RUNTIME.find_parameter('Rate'), ...
    Text='AM Rate (Hz)');
gui.components.Parameter_Control(g, S.RUNTIME.find_parameter('StimDur'), Text='Stimulus Duration (ms)');
gui.components.Parameter_Control(g, S.RUNTIME.find_parameter('StimDelayList'), Type='range', ...
    Text='Stimulus Delay (ms)');
gui.components.Parameter_Control(g, S.RUNTIME.find_parameter('ITIDur'), BoundProperty='isRandom', ...
    Type='checkbox', Text='Randomize ITI');
gui.components.Parameter_Control(g, S.RUNTIME.find_parameter('DropPellet'), Type='momentary', ...
    Text='Drop Pellet');

% One staged edit, so the "edited but not committed" highlight is visible.
C.Value = 12;
end


function fig = shotParameterUpdate(S)
fig = shotFigure([360 190]);
g = uigridlayout(fig, [3 1]);
g.RowHeight = {34, 34, 40};
g.Padding = [10 10 10 10];

c1 = gui.components.Parameter_Control(g, S.RUNTIME.find_parameter('Rate'), Text='AM Rate (Hz)');
c2 = gui.components.Parameter_Control(g, S.RUNTIME.find_parameter('NumPellets'), Text='Pellets per Reward');

U = gui.components.Parameter_Update(S.RUNTIME, g);
U.watchedHandles = [c1 c2];
c1.Value = 12;   % stage an edit: the button turns green and says so
end


function fig = shotMonitorTable(S)
fig = shotFigure([510 195]);
P = [S.RUNTIME.find_parameter('Depth'), S.RUNTIME.find_parameter('StimDelay'), ...
    S.RUNTIME.find_parameter('RespWinDelay'), S.RUNTIME.find_parameter('RespLatency'), ...
    S.RUNTIME.find_parameter('RespCode'), S.RUNTIME.find_parameter('InTrial')];
gui.components.Parameter_Monitor(fig, P, type='table', pollPeriod=0.5, ...
    Columns=["Type","UpdateEveryTrial"], PreferenceTag="wikiShotMonitorTable");
end


function fig = shotMonitorGraphical(S)
fig = shotFigure([300 125]);
P = [S.RUNTIME.find_parameter('InTrial'), S.RUNTIME.find_parameter('RespWindow'), ...
    S.RUNTIME.find_parameter('StimDelay'), S.RUNTIME.find_parameter('RespLatency')];
gui.components.Parameter_Monitor(fig, P, type='graphical', pollPeriod=0.5, ...
    PreferenceTag="wikiShotMonitorGraphical");
end


%% ------------------------------------------------------------------------
%  Trial and session state
% -------------------------------------------------------------------------
function fig = shotNextTrial(S)
% StimDelayList rather than StimDelay: this paradigm draws the delay from a
% block sequence at dispatch, so the compiled table holds the parameter's floor
% in the StimDelay column and the condition's list bound in this one.
fig = shotFigure([330 165]);
gui.components.NextTrial(S.RUNTIME, fig, FontSize=14, PreferenceTag='wikiShotNextTrial', ...
    Fields=["TrialType","Depth","StimDelayList","ITIDur"]);
pushTrial(S);
end


function fig = shotSessionClock(S)
% The clock lays itself out in a grid; given a bare figure its panel takes a
% default position and the lines land off-screen. Hand it a layout cell.
%
% StartTime is wound to now minus the session's REAL duration: the clock reads
% the wall clock, so the file's own August start would show the elapsed line
% in days.
fig = shotFigure([300 130]);
g = uigridlayout(fig, [1 1]);
g.Padding = [4 4 4 4];

was = S.RUNTIME.StartTime;
S.RUNTIME.StartTime = datetime('now') - (S.DATA(end).computerTimestamp - was);
cleanup = onCleanup(@() setStartTime(S.RUNTIME, was));

c = gui.components.SessionClock(g, PreferenceTag='wikiShotSessionClock', FontSize=13);
c.attachRuntime(S.RUNTIME);
c.start();
pushTrial(S);      % without a trial the two trial lines read "--"
pause(2.2)
c.refresh();
end


function fig = shotElapsedTrialTimer(S)
fig = shotFigure([300 70]);
g = uigridlayout(fig, [1 1]);
t = gui.components.ElapsedTrialTimer(g, FontSize=18, Prefix='Last trial: ', FontWeight='bold');
t.attachRuntime(S.RUNTIME);
t.start();
pause(3.2)   % let the counter run, so the shot shows a live clock not 00:00:00
end


function fig = shotModeIndicator(~)
fig = shotFigure([170 120]);
ind = gui.components.ModeIndicator(fig, FontSize=13);
ind.setState(hw.DeviceState.Record);
end


function fig = shotStatusBar(~)
fig = shotFigure([560 80]);
sb = gui.components.StatusBar(fig, Position=[15 22 530 36]);
sb.setStatus('Protocol compiled: 21 conditions.', 'Press Run to start the session.');
end


%% ------------------------------------------------------------------------
%  Online analysis
% -------------------------------------------------------------------------
function fig = shotHistory(S)
% gui.components.History reads responseBits, so it wants a psychophysics.Psych
% subclass; psychophysics.Detection is not one. A Staircase in offline mode
% is the same object a real behavior GUI hands it.
fig = shotFigure([540 300]);
sc = psychophysics.Staircase(S.DATA, S.RUNTIME.find_parameter('StimDelay'));
H = gui.components.History(sc, fig, PreferenceTag='wikiShotHistory');
% green hit, red miss, blue correct reject, orange false alarm, yellow abort
H.BitColors               = ["#c8ffd9","#ffcdcd","#b3e1ff","#ffeacf","#faffcc"];
H.ParametersOfInterest    = {'StimDelay','TrialType'};
H.ParameterColumnFormats  = {'%.0f','%d'};
H.update();
end


function fig = shotSessionPerformance(S)
fig = shotFigure([340 175]);
p = uipanel(fig, 'Title', 'Session Performance', 'Units', 'normalized', 'Position', [0 0 1 1]);
gui.components.SessionPerformance(S.DATA, p, PreferenceTag='wikiShotSessionPerformance');
end


function fig = shotParameterScatter(S)
fig = shotFigure([700 380]);   % narrower and the colorbar's outcome names clip
gui.components.ParameterScatter(S.DATA, fig, PreferenceTag='wikiShotScatter', ...
    XParameter='StimDelay', YParameter='RespLatency', ColorParameter='Response');
end


function fig = shotPsychPlot(S)
fig = shotFigure([520 360]);
ax = axes(uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 1]));
gui.components.PsychPlot(S.Psych, ax);
S.PsychRUNTIME.EVENTS.notify('NewData', S.PsychTrialsEvent);
end


function fig = shotPerformance(S)
fig = shotFigure([540 185]);
P = gui.components.Performance(S.Psych, fig);
P.ParametersOfInterest = {'Depth'};
S.PsychRUNTIME.EVENTS.notify('NewData', S.PsychTrialsEvent);
end


function fig = shotSlidingWindow(S)
fig = shotFigure([580 320]);
ax = axes(uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 1]));
W = gui.components.SlidingWindowPerformancePlot(S.Psych, ax);
% 100 rather than the usual 30: only a fifth of the trials carry a stimulus and
% they are spread over five depths, so a 30-trial window is empty at most
% depths most of the time and the traces come out as square waves.
W.windowSize = 100;
replayTrials(S);   % this one plots per-trial history, so it needs the trials one at a time
end


function fig = shotOnlinePlot(~)
% The only shot that has to be driven in REAL TIME: gui.components.OnlinePlot stamps every
% sample with its own tic, so a window's worth of traces takes a window's worth
% of seconds to fill. A finished session is no use here — it holds trial
% outcomes, not the sub-second digital activity this component shows — so the
% box is mocked with BatchProbeInterface and animated. The trace names are the
% appetitive rig's own bits.
fig = shotFigure([680 380]);
ax = axes(uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 1]));

rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
iface = BatchProbeInterface();

names = {'Platform','Trough','InTrial','DelayPeriod','RespWindow','PelletDrop'};
P = hw.Parameter.empty(1,0);
for i = 1:numel(names)
    p = iface.add_parameter(names{i}, 0);
    p.Value = 0;
    iface.put(p, 0);
    P(i) = p;
end
pTrig = iface.add_parameter('_TrigState~1', 0); iface.put(pTrig, 0);
pNum  = iface.add_parameter('_TrialNum~1',  1); iface.put(pNum,  1);
rt.Interfaces = iface;

op = gui.components.OnlinePlot(rt, P, ax, 1, PreferenceTag='wikiShotOnlinePlot');
fig.UserData = {op, iface};   % closeFigure deletes these, and the timer with them

% Drive the samples by hand: stop the component's own timer, seat its clock the
% way its StartFcn would, and step it so the loop controls the sample rate.
stop(op.h_timer);
if op.startTic_ == 0
    op.h_timer.Timer.StartFcn(op.h_timer.Timer, []);
end
op.redrawPeriod = 0;

span = abs(diff(seconds(op.timeWindow)));   % run the full width, or the axis opens half empty
trial = 1;
lastTrial = -inf;
t0 = tic;
while toc(t0) < span
    ph = toc(t0);
    for i = 1:numel(P)
        on = mod(ph + i*0.37, 1.1 + 0.25*i) < (0.25 + 0.08*i);
        iface.put(P(i), double(on));
    end
    if ph - lastTrial > 2.5
        iface.put(pTrig, 1);
        trial = trial + 1;
        iface.put(pNum, trial);
        lastTrial = ph;
    else
        iface.put(pTrig, 0);
    end
    op.update();
    pause(op.periodNom);   % the ring is sized from the timer period; sampling faster fills only part of the window
end
end


function fig = shotBufferPlot(S)
% Mocked, for the same reason gui.components.OnlinePlot and gui.components.SyringePump are: the
% session has nothing to show. The appetitive rig declares exactly ONE
% buffer parameter, FIRcoefs, and it is a 'Coefficient Buffer' -- the
% session-static type gui.components.BufferPlot deliberately refuses to plot -- so no
% saved file in the lab carries a per-trial Buffer for this to draw.
%
% What is real: the offline path (a DATA struct array is one of the
% component's three documented sources, and the one a review uses), the
% three trials, their indices, and the AM parameters the traces are built
% from -- each waveform is the fully modulated 10 Hz AM noise burst the rig
% played on that trial, and each sensor trace steps at that trial's own
% recorded response latency.
fig = shotFigure([700 380]);

fs   = 24414.0625;   % the TDT sample rate this rig runs at
pre  = 0.1;          % s of baseline before the burst
post = 0.25;         % ... and after it, long enough to hold the whole trough contact
amp  = 0.45;         % V RMS at the modulation peak, the swing this rig's DAC runs at
rs   = RandStream('twister', 'Seed', 11);   % its own stream: a shot must not move the global one

D = S.DATA([S.DATA.TrialType] == 0);   % stimulus trials; a catch trial has no burst
D = D(end-2:end);                      % three of them, newest last
for k = 1:numel(D)
    dur = D(k).StimDur / 1000;
    t   = (0:1/fs:(pre + dur + post))';
    m   = 10^(D(k).Depth/20);          % the rig states AM depth in dB re 100%

    env = zeros(size(t));
    on  = t >= pre & t < pre + dur;
    env(on) = amp * (1 - m * (1 + cos(2*pi*D(k).Rate*(t(on)-pre)))/2);
    D(k).StimWaveform = env .* randn(rs, numel(t), 1);

    % The trough sensor going high when the animal collects: this session
    % recorded the latency, so the step lands where it landed.
    hit = t >= pre + D(k).RespLatency/1000 & t < pre + D(k).RespLatency/1000 + 0.15;
    D(k).TroughSensor = 0.9*hit + 0.012*randn(rs, numel(t), 1);
end

p = gui.components.BufferPlot(D, fig, Buffers={'StimWaveform','TroughSensor'}, ...
    SampleRate=fs, XAxisUnits='milliseconds', NumTrialsShown=3, ...
    PreferenceTag='wikiShotBufferPlot');
fig.UserData = p;   % closeFigure deletes it, dropping its listeners
end


%% ------------------------------------------------------------------------
%  Session control
% -------------------------------------------------------------------------
function fig = shotSessionGate(~)
% Both states in one shot: the gate as it opens, and the status line it
% becomes. A picture of the armed button alone would not show the thing
% that is easy to miss -- that the button never goes away.
fig = shotFigure([300 130]);
g = uigridlayout(fig, [2 1]);
g.RowHeight = {36, 36};
g.Padding = [12 12 12 12];

gui.components.SessionGate(g);                       % armed, as the session opens

retired = gui.components.SessionGate(g);             % the same button after the press
retired.release();
end


function fig = shotRegenerateTrial(S)
% Both states in one shot, the way shotSessionGate photographs the gate: the
% button as it sits for almost all of a session (dead, washed out) and the
% same button with Ctrl+Alt+Shift held (live, amber). One state alone would
% not show the thing that matters -- that this button is unreachable until
% the operator makes a two-handed gesture.
%
% Neither state is painted by hand. The run mode is the one a running box is
% in, broadcast exactly as epsych.RunExpt's PsychTimerStart broadcasts it,
% and the armed button is armed through its own gui.KeyBindings by a
% synthesized key event -- the same route the smoke test uses. Two buttons
% on one figure would share that figure's dispatcher and arm together, so
% the armed one is given a KeySource of its own on a figure of its own.
fig = shotFigure([430 120]);
g = uigridlayout(fig, [2 2]);
g.RowHeight   = {36, 36};
g.ColumnWidth = {'1x', 180};
g.Padding     = [12 12 12 12];

lbl = uilabel(g, 'Text', 'Ctrl+Alt+Shift not held  ->', 'HorizontalAlignment', 'right');
lbl.Layout.Row = 1; lbl.Layout.Column = 1;
idle = gui.components.RegenerateTrial(S.RUNTIME, g);   % this figure's shared dispatcher, never typed into

lbl = uilabel(g, 'Text', 'Ctrl+Alt+Shift held  ->', 'HorizontalAlignment', 'right');
lbl.Layout.Row = 2; lbl.Layout.Column = 1;
keyFig = uifigure('Visible', 'off', 'Tag', 'wikiComponentShot', 'Name', '');
keys   = gui.KeyBindings(keyFig);
live   = gui.components.RegenerateTrial(S.RUNTIME, g, KeySource=keys);

% Both buttons follow ModeChange rather than reading the mode at
% construction, so the broadcast has to come after they exist.
S.RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Record));
keys.dispatchKeyPress(struct('Key','shift', ...
    'Modifier',{{'control','alt','shift'}}, 'Character',''));

assert(live.Armed && ~idle.Armed, 'generate_component_screenshots:NotArmed', ...
    'the armed button did not arm, so the shot would show two identical states')

fig.UserData = {idle, live, keys, keyFig};
end


function fig = shotKeyBindings(S)
% The shortcut list itself, which is the only place the bound set is ever
% visible: there is no rebinding UI, because bindings are code.
%
% Driven from a real gui.BehaviorGUI (tmp/WikiKeysBehaviorGUI) rather than
% by binding chords here, so every line in the picture is one a paradigm
% would really have: the base class's own two help chords, the default
% chords three add* helpers ship with, and two subject-response arrow keys
% bound in build the way examples/two_afc binds its own.
G = WikiKeysBehaviorGUI(S.RUNTIME);

% showHelp builds its window for an operator to look at, so it comes up
% visible and modal. Hidden again immediately: the gallery is captured off
% screen, and a modal window would sit over the rest of the run.
before = findall(groot, 'Type', 'figure');
G.Keys.showHelp();
fig = setdiff(findall(groot, 'Type', 'figure'), before);
assert(isscalar(fig), 'generate_component_screenshots:NoHelpWindow', ...
    'showHelp did not open exactly one window')
fig.WindowStyle = 'normal';
fig.Visible     = 'off';
fig.Tag         = 'wikiComponentShot';
fig.UserData    = G;   % closeFigure deletes the GUI, which closes its own figure
end


function fig = shotPhaseSelector(S)
% The rig's real phase files, copied to a scratch folder so the shot cannot
% write to the lab's protocol share.
phaseDir = fullfile(tempdir, 'epsych_wiki_phases');
if isfolder(phaseDir), rmdir(phaseDir, 's'); end
mkdir(phaseDir);
src = dir(fullfile(S.Options.PhaseDir, '*.eprot'));
assert(~isempty(src), 'generate_component_screenshots:NoPhases', ...
    'No .eprot files in "%s"', S.Options.PhaseDir)
for k = 1:numel(src)
    copyfile(fullfile(src(k).folder, src(k).name), fullfile(phaseDir, src(k).name));
end

fig = shotFigure([420 145]);
ps = gui.components.PhaseSelector(S.RUNTIME, phaseDir);
ps.PhasePath = phaseDir;     % outrank any saved directory preference
ps.createGUI(fig);
% The phase this session actually ran, when it is there; otherwise the middle
% of whatever the folder holds.
want = find(contains(ps.Names, "StimDelay"), 1);
if isempty(want), want = ceil(numel(ps.Names)/2); end
ps.h_PhaseSelect.Value = ps.Names(want);
ps.onPhaseSelectionChanged(ps.h_PhaseSelect);
end


function fig = shotStaircaseTraining(S)
% Over Depth, with the step sizes the paradigm itself carries
% (Depth_StepOnMiss / Depth_StepOnHit) and the parameter's own limits.
P = S.RUNTIME.find_parameter('Depth');
fig = shotFigure([560 320]);   % the table is fixed-height; less clips a row
gui.StaircaseTraining(P, Parent=fig, ...
    MinValue=P.Min, MaxValue=P.Max, ...
    StepUp=abs(S.RUNTIME.find_parameter('Depth_StepOnMiss').Value), ...
    StepDown=abs(S.RUNTIME.find_parameter('Depth_StepOnHit').Value), ...
    StepUpResponse="Miss", StepDownResponse="Hit");
end


function fig = shotSyringePump(~)
% Over the in-process pump mock, so the panel shows a connected link and a
% real dispensed volume rather than the disconnected state. Nothing to take
% from the session file: the appetitive rig rewards with pellets, not a pump.
mock = NE1000_Mock(SyringeDiameter=21.59);
mock.SimInfused = 0.836;              % mL, the units the panel displays by default

fig = shotFigure([380 330]);
p = gui.components.SyringePump(mock, fig, PreferenceTag='wikiShotSyringePump');
p.refresh();
fig.UserData = {p, mock};             % closeFigure tears both down
end


function fig = shotParameterDebugger(S)
% A whole window rather than a component, so this returns the debugger's own
% figure. Pointed at the session's protocol and swept once, so the table shows
% real parameters with real values and the read colouring the window is about.
D = gui.ParameterDebugger(S.RUNTIME, Visible=false);
fig = D.H.figure;
fig.Position = [200 200 1180 520];
D.readAll();
end


function fig = shotFilenameValidator(S)
fig = shotFigure([540 72]);
g = uigridlayout(fig, [1 1]);
g.Padding = [8 8 8 8];
[~, stem] = fileparts(S.RUNTIME.TRIALS(1).DataFilename);
gui.components.FilenameValidator(S.RUNTIME, g, stem);
end


function fig = shotComponentToolbar(S)
% The toolbar is figure chrome, so this is a whole (small) behavior GUI
% rather than a component in a bare figure. Four tools: the two lazy entries
% declared in build, then a separator, then the two registered gui.PopOut
% components — discovered only after build returned.
G = WikiToolbarBehaviorGUI(S.RUNTIME);
fig = G.h_figure;
pushData(S);      % the scatter is empty until the session is re-broadcast
pushTrial(S);     % and the upcoming-trial panel reads "--"
end


function fig = shotNotes(S)
% The panel form with a few notes already in the log, beside the button form.
% Notes go into the shared session's store, so the trial stamps are the real
% session's own rather than invented.
fig = shotFigure([560 250]);
g = uigridlayout(fig, [2 2]);
g.RowHeight    = {'1x', 26};
g.ColumnWidth  = {'1x', 96};
g.Padding      = [8 8 8 8];

panel = gui.components.Notes(S.RUNTIME, g, PreferenceTag='wikiShotNotes');
panel.LogH.Parent.Layout.Row    = 1;
panel.LogH.Parent.Layout.Column = [1 2];

button = gui.components.Notes(S.RUNTIME, g, ButtonOnly=true, PreferenceTag='wikiShotNotesButton');
button.OpenH.Layout.Row    = 2;
button.OpenH.Layout.Column = 2;

lbl = uilabel(g, 'Text', 'the button form, for a GUI with no room for a log  ->', ...
    'HorizontalAlignment', 'right');
lbl.Layout.Row    = 2;
lbl.Layout.Column = 1;

% epsych.SessionNotes.fromSnapshot leaves the store unbound on purpose -- a
% review has no session to stamp against -- and an unbound store renders every
% elapsed time as --:--:--. Bind it to the runtime, which is the state a live
% session's store is in.
S.RUNTIME.NOTES.RUNTIME = S.RUNTIME;

% Trial and Time are stated so the three notes sit where they would have been
% typed across the session; the store would otherwise stamp all three with the
% trial the session ended on and the same second.
t0 = S.RUNTIME.StartTime;
S.RUNTIME.NOTES.add('animal on platform, weight 24.1 g', Trial=0,  Time=t0);
S.RUNTIME.NOTES.add('pellet hopper jammed, cleared', Trial=18, Time=t0+minutes(3)+seconds(41));
S.RUNTIME.NOTES.add('holding well past 3 s - step the delay up', Trial=44, Time=t0+minutes(8)+seconds(52));

fig.UserData = {panel, button};   % closeFigure deletes both, dropping their listeners
end


function fig = shotScreenCapture(~)
% Both button forms side by side. copyToClipboard is deliberately NOT called:
% it would put the shot on the developer's own clipboard.
fig = shotFigure([300 66]);
g = uigridlayout(fig, [1 2]);
g.ColumnWidth = {36, '1x'};
g.Padding = [10 10 10 10];
icon = gui.components.ScreenCapture(g);
labeled = gui.components.ScreenCapture(g, Text='Screenshot');
fig.UserData = {icon, labeled};   % closeFigure deletes both, stopping their timers
end


function fig = shotBehaviorGUIHelpers(S)
% The helpers gui.BehaviorGUI itself provides: a row of trigger buttons, a titled
% control column ending in an update button, and a polled monitor.
G = WikiHelperBehaviorGUI(S.RUNTIME);
fig = G.h_figure;
end


%% ------------------------------------------------------------------------
%  Utilities
% -------------------------------------------------------------------------
function fig = shotFigure(sz)
fig = uifigure('Visible', 'off', 'Position', [200 200 sz(1) sz(2)], ...
    'Tag', 'wikiComponentShot', 'Name', '');
end


function setStartTime(rt, t)
if isvalid(rt), rt.StartTime = t; end
end


function closeFigure(fig)
% A gui.BehaviorGUI parks itself in the figure's UserData, and a shot may park a
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
    'epsych2_gui_Notes', 'epsych2_gui_BufferPlot', ...
    'StaircaseTraining', 'wikiShotSessionClock', 'wikiShotKeyBindings', ...
    'wikiShotBehaviorGUIHelpers', 'wikiShotComponentToolbar'};
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
