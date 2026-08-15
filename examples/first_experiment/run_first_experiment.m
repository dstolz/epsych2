function [RUNTIME, GUI] = run_first_experiment(options)
% [RUNTIME, GUI] = run_first_experiment(Name=Value, ...)
% Run the first-experiment tutorial end-to-end with one command: load (or
% create) the tutorial protocol, stand up an epsych.Runtime around its
% hw.Software interface, launch FirstExperimentBehaviorGUI, and start the same
% timer loop a real session runs (ep_TimerFcn_RunTime on every tick). YOU
% then perform the task — press RESPOND when the lamp flashes — and every
% completed trial is journaled and collected exactly as in a real session.
%
% The session ends by itself after NumTrials trials, or when you close the
% GUI window; either way the data file is written automatically and its
% path printed. Analyze it with explore_first_data (same folder).
%
% This driver is the scripted equivalent of pressing Run in epsych.RunExpt:
% it performs the same three timer-function calls (Start / RunTime / Stop)
% on the same runtime machinery. The wiki walkthrough runs the identical
% session through the RunExpt GUI instead.
%
% Options:
%   NumTrials    - Trials to run before auto-stop (default 40)
%   SubjectName  - Name recorded in the session data (default 'Me')
%   ProtocolFile - .eprot to run; created if missing (default: FirstExperiment.eprot here)
%   DataPath     - Folder for data files (default: data/ here)
%   Test         - Mark the session as test data, like RunExpt's Preview (default false)
%
% Returns:
%   RUNTIME - The live epsych.Runtime; the session keeps running in its
%             timer after this function returns, just as with RunExpt.
%   GUI     - The FirstExperimentBehaviorGUI instance.
%
% Try it:
%   run_first_experiment                 % 40 trials, then auto-save
%   run_first_experiment(NumTrials=15)   % a quick taste
%
% Walkthrough: https://github.com/dstolz/epsych2/wiki/Your-First-Experiment
%
% See also create_first_protocol, FirstExperimentBehaviorGUI, explore_first_data

arguments
    options.NumTrials (1,1) double {mustBeInteger, mustBePositive} = 40
    options.SubjectName (1,:) char = 'Me'
    options.ProtocolFile (1,:) char = ''
    options.DataPath (1,:) char = ''
    options.Test (1,1) logical = false
end

here = fileparts(mfilename('fullpath'));
addpath(here); % FirstExperimentBehaviorGUI must be resolvable by name

if isempty(options.ProtocolFile)
    options.ProtocolFile = fullfile(here, 'FirstExperiment.eprot');
end
if ~isfile(options.ProtocolFile)
    create_first_protocol(options.ProtocolFile);
end
if isempty(options.DataPath)
    options.DataPath = fullfile(here, 'data');
end
if ~isfolder(options.DataPath), mkdir(options.DataPath); end

% --- Load and compile the protocol ---------------------------------------
P = epsych.Protocol.load(options.ProtocolFile);
if P.needsCompile, P.compile(); end
assert(P.COMPILED.ntrials > 0, ...
    'Protocol failed to compile - run P.validate() for the reasons.')

% --- Runtime scaffold: what RunExpt does before pressing Run -------------
RUNTIME = epsych.Runtime;
RUNTIME.isTest = options.Test;
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;   % connects the hw.Software backend
RUNTIME.TempDataDir = options.DataPath; % crash-recovery seed .mat + .epj journal
RUNTIME.DefaultDataPath = options.DataPath;

CONFIG = struct( ...
    'PROTOCOL', P, ...
    'SUBJECT', epsych.DefaultSubject(struct('Name', options.SubjectName, ...
        'Species', 'Human', 'Sex', 'Unknown', 'BoxID', 1)));

% The real session-start function: builds TRIALS, creates the trial
% selector, seeds the crash-recovery file and journal, and dispatches
% trial 1 (the TRIALS setter resolves the core triggers on the way in).
RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);

% RunExpt launches the behavior GUI right after Start, then broadcasts the
% session mode; mirror that order here.
GUI = FirstExperimentBehaviorGUI(RUNTIME);

% The real runtime loop: ep_TimerFcn_RunTime on every tick, wrapped so the
% session can end itself (trial quota reached, or the GUI was closed).
t = timer( ...
    Name = 'FirstExperimentTimer', ...
    Period = 0.05, ...
    ExecutionMode = 'fixedSpacing', ...
    BusyMode = 'drop', ...
    TimerFcn = @(tt,~) sessionTick(tt, RUNTIME, GUI, options.NumTrials), ...
    ErrorFcn = @(tt,evt) vprintf(0,1,'Session timer error: %s', evt.Data.message));
RUNTIME.TIMER = t;
start(t);

if options.Test
    runMode = hw.DeviceState.Preview;
else
    runMode = hw.DeviceState.Record;
end
RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(runMode));

vprintf(0, 'Session running: %d trials. Watch the lamp; press RESPOND when it flashes.', ...
    options.NumTrials)
vprintf(0, 'The session saves and stops by itself; closing the GUI window also ends it.')

if nargout == 0, clear RUNTIME GUI; end
end


function sessionTick(t, RUNTIME, GUI, numTrials)
% One tick of the session: end it when due, otherwise run the real
% per-tick trial processing.
try
    guiGone = isempty(GUI) || ~isvalid(GUI) || ...
        isempty(GUI.h_figure) || ~isvalid(GUI.h_figure);
    quotaMet = RUNTIME.TRIALS(1).TrialIndex > numTrials;
    if guiGone || quotaMet
        finishSession(t, RUNTIME);
        return
    end
    ep_TimerFcn_RunTime(RUNTIME);
catch ME
    vprintf(0, 1, ME)
    stop(t)
end
end


function finishSession(t, RUNTIME)
% What RunExpt's Stop button does: stop the timer, run the Stop timer
% function (idle broadcast, journal merge, log flush), then save. RunExpt
% saves through FUNCS.SavingFcn when the operator presses Save Data; here
% the file is written directly, in the layout of cl_SaveDataFcn.
stop(t)
try
    ep_TimerFcn_Stop(RUNTIME);
catch ME
    vprintf(0, 1, ME)
end

if ~isfield(RUNTIME.TRIALS, 'DATA') || isempty(RUNTIME.TRIALS(1).DATA)
    vprintf(0, 'Session ended before any trial completed - nothing to save.')
    return
end

Data = RUNTIME.TRIALS(1).DATA;
Info = EPsychInfo().meta;
fn = RUNTIME.TRIALS(1).DataFilename;
if ~isfolder(fileparts(fn)), mkdir(fileparts(fn)); end
save(fn, 'Data', 'Info')
vprintf(0, 'Session complete: %d trials saved to %s', numel(Data), fn)
vprintf(0, 'Next: explore_first_data(''%s'')', fn)
end
