function ran = warmUp(options)
% ran = epsych.warmUp()
% ran = epsych.warmUp(Force=true, NumTrials=6, Displays=true)
% tf  = epsych.warmUp(Query=true)
% Run a few trial boundaries of a small software-only session, so the code a
% real boundary runs has already been executed when the first real one comes.
%
% The first trial boundaries after MATLAB starts are several times slower
% than the rest. On the rig the subject waited 384, 184, 119 and 126 ms at
% the first four against 75 ms later. A second session in the same MATLAB
% started at 167 ms and was at 80 ms by its second trial: most of the cost
% belongs to MATLAB not having run that code yet, not to the session. So this
% runs it, once per MATLAB session: the real trial loop (ep_TimerFcn_Start,
% ep_TimerFcn_RunTime, ep_TimerFcn_Stop) over an hw.Software protocol built
% here -- roved and fixed parameters, two Expressions, the three trial
% triggers -- with the analysis objects a behavior GUI computes through
% (psychophysics.Staircase, psychophysics.SessionMetrics) listening.
%
% That takes about 2 s in a MATLAB that has run nothing, and its own
% boundaries show what it buys: 209, 80, 45, 46, 72, 33 ms.
%
% Displays=true also builds one of each standard display and two parameter
% controls in a window that is never shown, and flushes the graphics after
% each boundary. That is the larger part of what a first real boundary costs
% the MATLAB thread -- and of what this costs: about 12 s, nearly all of it
% building the window and drawing it the first time. Too long to put in front
% of a Run; it is there for idle time, called by hand or from a startup file.
%
% Nothing of the real session is touched -- not its runtime, hardware,
% behavior GUI, roster or data; the rehearsal's own files go to a folder in
% tempdir that is removed when it ends. That is also its limit: a paradigm's
% own trial selector and behavior GUI, and a hardware backend's read and
% write paths, are not rehearsed, so the first real boundary is still slower
% than the hundredth.
%
% epsych.RunExpt calls this at Run and Preview, before the hardware starts,
% and it does nothing after the first time. Preference EPsych/WarmUp = false
% turns that call off (the preference is read behind ispref and never
% created here). A rehearsal that fails is logged and not retried: it must
% never be the reason a session does not start.
%
% Name=Value options:
%   Force     - run even if it already ran, and whatever the preference says.
%               Default false
%   NumTrials - boundaries to rehearse. Default 6, about what they take to
%               settle
%   Displays  - also rehearse the displays, in a hidden window. Default false
%   Query     - only report whether a call would run now. Default false
%
% Returns:
%   ran - true when a rehearsal ran (or, with Query, would run).
%
% See also: epsych.RunExpt, ep_TimerFcn_RunTime, epsych.TickStats,
%           documentation/overviews/Runtime_Performance.md

arguments
    options.Force (1,1) logical = false
    options.NumTrials (1,1) double {mustBePositive, mustBeInteger} = 6
    options.Query (1,1) logical = false
    options.Displays (1,1) logical = false
end

persistent done
wanted = options.Force || (isempty(done) && localEnabled());
ran = wanted;
if options.Query || ~wanted
    return
end
done = true;        % before the attempt: a failure is not retried at every Run

t0 = tic;
vprintf(1, 'Warm-up: rehearsing %d trial boundaries on a software-only session', options.NumTrials)
try
    T = localRehearse(options.NumTrials, options.Displays);
    vprintf(1, 'Warm-up: done in %.1f s (%.1f s setting up; boundaries took %s ms)', ...
        toc(t0), T.Build, strjoin(compose('%.0f', T.Boundary * 1e3), ', '))
catch ME
    ran = false;
    vprintf(0, 1, ME);
    vprintf(0, 1, 'Warm-up: the rehearsal failed and was abandoned; the session is not affected.')
end
end


function tf = localEnabled()
% The rig's choice. A preference that does not exist means yes.
tf = true;
if ispref('EPsych', 'WarmUp')
    v = getpref('EPsych', 'WarmUp');
    if isscalar(v) && (islogical(v) || isnumeric(v))
        tf = logical(v);
    end
end
end


function T = localRehearse(numTrials, displays)
tBuild = tic;
TAG = 'epsychWarmUp';
scratch = fullfile(tempdir, sprintf('epsych_warmup_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));
localRmPrefs(TAG);
cleanupPrefs = onCleanup(@() localRmPrefs(TAG));

% --- a protocol with one of each thing a dispatch does -----------------------
P = epsych.Protocol(Info = 'epsych.warmUp');
sw = P.SoftwareModule;                                        % the hw.Software interface
level = sw.add_parameter('Level', [-6 -8 -10]);              % roved
sw.add_parameter('TrialType', [0 1], Type = 'Integer');
fixed = sw.add_parameter('Fixed', 5);
p = sw.add_parameter('Derived', 0);
p.Expression = "Fixed + 250";                                 % a sibling reference
p = sw.add_parameter('Qualified', 0);
p.Expression = string(sw.Module(1).Name) + ".Fixed .* 2";     % a Module.Parameter one
resp = sw.add_parameter('RespCode', 0, Type = 'Integer');
resp.UpdateEveryTrial = false;                                % set by hand below, as a device would
resp.Value = 0;
for nm = ["x_NewTrial_1" "x_ResetTrig_1" "x_TrialComplete_1"]
    sw.add_parameter(char(nm), 0, isTrigger = true);
end
P.compile();

CONFIG = struct('PROTOCOL', P, 'SUBJECT', struct('Name', 'WarmUp', 'BoxID', 1));

RUNTIME = epsych.Runtime;
cleanupRuntime = onCleanup(@() localDelete({RUNTIME}));
RUNTIME.isTest = true;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(fullfile(scratch, 'warmup_session.mat'));
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;
set(RUNTIME.Interfaces, 'mode', hw.DeviceState.Preview);
RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);                 % dispatches trial 1

% --- what listens to a boundary ----------------------------------------------
% Always the analysis a behavior GUI computes through. With displays, also
% what it shows, in a window that is never shown.
stair = psychophysics.Staircase(RUNTIME, level);
metrics = psychophysics.SessionMetrics(RUNTIME);
cleanupAnalysis = onCleanup(@() localDelete({metrics, stair}));
if displays
    fig = uifigure('Visible', 'off', 'Tag', TAG, 'HandleVisibility', 'off');
    cleanupFig = onCleanup(@() localDelete({fig}));
    g = uigridlayout(fig, [2 3]);
    stair.Plot(uiaxes(g));
    shown = { ...
        gui.components.History(stair, uipanel(g), PreferenceTag = TAG), ...
        gui.components.ParameterScatter(RUNTIME, uipanel(g), PreferenceTag = TAG), ...
        gui.components.SessionPerformance(RUNTIME, uipanel(g), PreferenceTag = TAG), ...
        gui.components.NextTrial(RUNTIME, uipanel(g), PreferenceTag = TAG), ...
        gui.components.Parameter_Control(uigridlayout(uipanel(g), [2 2]), fixed, Type = 'editfield'), ...
        gui.components.Parameter_Control(uigridlayout(uipanel(g), [2 2]), level, Type = 'editfield')};
    cleanupShown = onCleanup(@() localDelete(shown));
end
RUNTIME.EVENTS.DeferralEnabled = true;                        % the deferred path is the lab GUI's
T = struct('Build', toc(tBuild), 'Boundary', zeros(1, numTrials));

% --- the boundaries -----------------------------------------------------------
% Hits and misses on both trial types, so the staircase steps and reverses
% and every display has more than one kind of row to draw.
codes = [ ...
    localMask([epsych.BitMask.Hit epsych.BitMask.TrialType_0]), ...
    localMask([epsych.BitMask.Miss epsych.BitMask.TrialType_0]), ...
    localMask([epsych.BitMask.CorrectReject epsych.BitMask.TrialType_1]), ...
    localMask([epsych.BitMask.Hit epsych.BitMask.TrialType_0]), ...
    localMask([epsych.BitMask.FalseAlarm epsych.BitMask.TrialType_1])];
for k = 1:numTrials
    resp.Value = codes(mod(k - 1, numel(codes)) + 1);
    tb = tic;
    RUNTIME.TRIALS(1).FORCE_TRIAL = true;
    RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
    if displays, drawnow; end                                 % and the flush that follows a boundary
    T.Boundary(k) = toc(tb);
end

ep_TimerFcn_Stop(RUNTIME);
end


function localDelete(things)
for k = 1:numel(things)
    h = things{k};
    if ~isempty(h) && isvalid(h), delete(h); end
end
end


function localRmPrefs(tag)
% The displays remember themselves by PreferenceTag; the rehearsal must leave
% nothing behind, nor start from what an interrupted one left.
groups = {'epsych2_gui_History', 'epsych2_gui_ParameterScatter', ...
    'epsych2_gui_SessionPerformance', 'epsych2_gui_NextTrial', 'epsych2_psychophysics_Staircase'};
for g = 1:numel(groups)
    if ispref(groups{g}, tag), rmpref(groups{g}, tag); end
end
end


function localRmdir(d)
if isfolder(d), rmdir(d, 's'); end
end


function m = localMask(bits)
% Response code with these epsych.BitMask bits set.
m = epsych.BitMask.Bits2Mask(uint32(bits));
end
