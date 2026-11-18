function [RUNTIME, GUI] = run_oddball_experiment(options)
% [RUNTIME, GUI] = run_oddball_experiment(Name=Value, ...)
% Run the auditory oddball example with one command: load (or create) the
% protocol, stand up an epsych.Runtime around its hw.Software interface,
% open OddballBehaviorGUI, and run the same timer loop a real session runs
% (ep_TimerFcn_RunTime on every tick). Nothing plays until you press Start
% in the GUI; Pause and Stop are there too.
%
% YOU are the subject: press RESPOND (or the space bar) when you hear a
% deviant -- a rising glide among the steady tones, with the default banks
% -- and let the standards go by. Every sound is a trial, journaled and
% recorded exactly as in a real session.
%
% The session ends when you press Stop, close the window, or reach
% NumTrials. Either way the data file is written automatically and its
% path printed; analyze it with explore_oddball_data (same folder).
%
% This is the scripted equivalent of pressing Run in epsych.RunExpt: the
% same Start / RunTime / Stop timer functions on the same runtime machinery.
% To run it from RunExpt instead, set a project's Behavior GUI to
% OddballBehaviorGUI and its protocol to Oddball.eprot.
%
% Options:
%   NumTrials     - Stop after this many trials (default Inf: until you press Stop)
%   SubjectName   - Name recorded in the session data (default 'Me')
%   ProtocolFile  - .eprot to run; created if missing (default: Oddball.eprot here)
%   DataPath      - Folder for data files (default: data/ here)
%   StandardFiles - Use these .wav files as the standard bank for this run
%   DeviantFiles  - Use these .wav files as the deviant bank for this run
%   Test          - Mark the session as test data, like RunExpt's Preview (default false)
%   WaitForBegin  - Hold at the GUI's Start button (default true). With false
%                   the session starts at once -- for scripts and tests.
%   PlayAudio     - Play the sounds (default true)
%
% Returns:
%   RUNTIME - The live epsych.Runtime; the session keeps running in its
%             timer after this function returns, just as with RunExpt.
%   GUI     - The OddballBehaviorGUI instance.
%
% Try it:
%   run_oddball_experiment                    % press Start, then listen
%   run_oddball_experiment(NumTrials = 60)    % stops by itself after 60 sounds
%
% See also create_oddball_protocol, OddballBehaviorGUI, OddballSelector,
%   explore_oddball_data

arguments
    options.NumTrials (1,1) double {mustBePositive} = Inf
    options.SubjectName (1,:) char = 'Me'
    options.ProtocolFile (1,:) char = ''
    options.DataPath (1,:) char = ''
    options.StandardFiles (1,:) string = string.empty(1,0)
    options.DeviantFiles (1,:) string = string.empty(1,0)
    options.Test (1,1) logical = false
    options.WaitForBegin (1,1) logical = true
    options.PlayAudio (1,1) logical = true
end

here = fileparts(mfilename('fullpath'));
addpath(here); % OddballBehaviorGUI and OddballSelector must resolve by name

if isempty(options.ProtocolFile)
    options.ProtocolFile = fullfile(here, 'Oddball.eprot');
end
if ~isfile(options.ProtocolFile)
    create_oddball_protocol(options.ProtocolFile);
end
if isempty(options.DataPath)
    options.DataPath = fullfile(here, 'data');
end
if ~isfolder(options.DataPath), mkdir(options.DataPath); end

% A previous run's session timer, left stopped, is only clutter; a RUNNING
% one is a session still going, and starting a second would interleave two
% sessions in one GUI.
old = timerfindall('Name', 'OddballTimer');
assert(~any(strcmp(get(old, 'Running'), 'on')), ...
    'An oddball session is already running - press Stop in its window first.')
delete(old)

% --- Load and compile the protocol ---------------------------------------
P = epsych.Protocol.load(options.ProtocolFile);
setBankForRun(P, 'StandardFiles', options.StandardFiles);
setBankForRun(P, 'DeviantFiles',  options.DeviantFiles);
if P.needsCompile, P.compile(); end
assert(P.COMPILED.ntrials > 0, ...
    'Protocol failed to compile - run P.validate() for the reasons.')

% --- Runtime scaffold: what RunExpt does before pressing Run -------------
RUNTIME = epsych.Runtime;
RUNTIME.isTest = options.Test;
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;       % connects the hw.Software backend
RUNTIME.TempDataDir = options.DataPath;  % crash-recovery seed .mat + .epj journal
RUNTIME.DefaultDataPath = options.DataPath;

CONFIG = struct( ...
    'PROTOCOL', P, ...
    'SUBJECT', epsych.DefaultSubject(struct('Name', options.SubjectName, ...
        'Species', 'Human', 'Sex', 'Unknown', 'BoxID', 1)));

% The real session-start function: builds TRIALS, creates OddballSelector
% (which picks trial 1 and writes its sound into StimFile), seeds the
% crash-recovery file and journal, and dispatches trial 1.
RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);

% The session timer exists BEFORE the GUI so the GUI's Stop button has
% something to stop. Its StopFcn winds the session up and saves, so every
% way of ending -- Stop, closing the window, the trial quota -- saves the
% same way, exactly once.
t = timer( ...
    Name = 'OddballTimer', ...
    Period = 0.02, ...
    ExecutionMode = 'fixedSpacing', ...
    BusyMode = 'drop', ...
    StopFcn = @(~,~) finishSession(RUNTIME), ...
    ErrorFcn = @(~,evt) vprintf(0, 1, 'Session timer error: %s', evt.Data.message));
RUNTIME.TIMER = t;

% RunExpt launches the behavior GUI right after Start, then broadcasts the
% run mode. With WaitForBegin the constructor holds at the Start button.
GUI = OddballBehaviorGUI(RUNTIME, WaitForBegin = options.WaitForBegin, ...
    PlayAudio = options.PlayAudio);

if ~isvalid(GUI)
    % The window was closed at the Start button: the run was called off.
    % Nothing to save, but the journal the Start function opened is closed.
    vprintf(0, 'Session called off before it started.')
    try
        ep_TimerFcn_Stop(RUNTIME);
    catch ME
        vprintf(0, 1, ME)
    end
    delete(t)
    if nargout == 0, clear RUNTIME GUI; end
    return
end

t.TimerFcn = @(tt,~) sessionTick(tt, RUNTIME, GUI, options.NumTrials);
start(t);

if options.Test
    runMode = hw.DeviceState.Preview;
else
    runMode = hw.DeviceState.Record;
end
RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(runMode));

vprintf(0, 'Oddball session running. Press RESPOND (or space) when you hear the odd one out.')
vprintf(0, 'Pause and Stop are in the GUI; the data file saves when the session ends.')

if nargout == 0, clear RUNTIME GUI; end
end


function sessionTick(t, RUNTIME, GUI, numTrials)
% One tick: end the session when due, otherwise the real per-tick trial
% processing.
try
    guiGone = isempty(GUI) || ~isvalid(GUI) || ...
        isempty(GUI.h_figure) || ~isvalid(GUI.h_figure);
    quotaMet = RUNTIME.TRIALS(1).TrialIndex > numTrials;
    if guiGone || quotaMet
        stop(t) % StopFcn saves
        return
    end
    ep_TimerFcn_RunTime(RUNTIME);
catch ME
    vprintf(0, 1, ME)
    stop(t)
end
end


function finishSession(RUNTIME)
% The session timer's StopFcn -- what RunExpt's Stop does: the Stop timer
% function (idle broadcast, journal merge, log flush), then the save. The
% file has the layout of RunExpt's saving functions plus the selector's
% sequences, so the stream can be reconstructed from the file alone.
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
Info = epsych.SessionSnapshot.forSubject(RUNTIME, 1); % includes the session notes
Sequences = struct();
try
    Sequences = RUNTIME.TRIALS(1).selector.sequenceRecord();
catch ME
    vprintf(1, 'Could not record the oddball sequences: %s', ME.message)
end
fn = RUNTIME.TRIALS(1).DataFilename;
if ~isfolder(fileparts(fn)), mkdir(fileparts(fn)); end
save(fn, 'Data', 'Info', 'Sequences')
vprintf(0, 'Session complete: %d trials saved to %s', numel(Data), fn)
vprintf(0, 'Next: explore_oddball_data(''%s'')', fn)
end


function setBankForRun(P, name, files)
% Override one bank for this run only: the loaded protocol object changes,
% the .eprot on disk does not. Value is what the session reads; Values too,
% so a session restart in the same protocol object keeps the choice.
if isempty(files), return; end
files = string(files);
for k = 1:numel(files)
    assert(isfile(files(k)), 'No such file: %s', files(k))
    [~, attr] = fileattrib(char(files(k)));
    files(k) = attr.Name;
end
p = [];
for iface = P.Interfaces
    p = iface.find_parameter(name, includeInvisible = true, silenceParameterNotFound = true);
    if ~isempty(p), break; end
end
assert(~isempty(p), 'Protocol has no %s parameter.', name)
p(1).Values = {cellstr(files)};
p(1).Value  = cellstr(files);
end
