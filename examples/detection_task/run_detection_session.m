function RUNTIME = run_detection_session(options)
% RUNTIME = run_detection_session(Name=Value, ...)
% Run the worked-example detection task end-to-end without hardware: load
% (or create) the example protocol, stand up an epsych.Runtime around its
% hw.Software interface, launch DetectionBoxGUI, run a simulated observer
% for NumTrials trials, and save a session data file that
% explore_saved_data.m can analyze.
%
% The trial loop mirrors what the real runtime does on every timer tick
% (ep_TimerFcn_RunTime): collect Read parameters into a DATA record, notify
% the selector, broadcast NewData, then select and dispatch the next trial
% (epsych.Runtime.dispatchNextTrial). The only simulation-specific part is
% the observer, which answers from a psychometric function instead of a rig.
%
% Options:
%   NumTrials    - Trials to run (default 120)
%   ShowGUI      - Launch DetectionBoxGUI (default true)
%   ProtocolFile - .eprot to run; created if missing (default: DetectionExample.eprot here)
%   DataPath     - Folder for the saved session file (default: data/ here)
%   Threshold    - Observer threshold, dB SPL (default 35)
%   Slope        - Psychometric slope, dB (default 8)
%   GuessRate    - False-alarm probability on catch trials (default 0.15)
%   LapseRate    - Miss probability at the easiest levels (default 0.05)
%   TrialPause   - Seconds between trials; set > 0 to watch the GUI update (default 0)
%   Seed         - rng seed for a reproducible session (default: leave rng alone)
%
% Try it:
%   run_detection_session(TrialPause=0.1);   % watch the GUI fill in
%
% Walkthrough: documentation/examples/Detection_Task_4_Running.md
%
% See also create_detection_protocol, DetectionBoxGUI, explore_saved_data

arguments
    options.NumTrials (1,1) double {mustBeInteger, mustBePositive} = 120
    options.ShowGUI (1,1) logical = true
    options.ProtocolFile (1,:) char = ''
    options.DataPath (1,:) char = ''
    options.Threshold (1,1) double = 35
    options.Slope (1,1) double {mustBePositive} = 8
    options.GuessRate (1,1) double {mustBeInRange(options.GuessRate,0,1)} = 0.15
    options.LapseRate (1,1) double {mustBeInRange(options.LapseRate,0,1)} = 0.05
    options.TrialPause (1,1) double {mustBeNonnegative} = 0
    options.Seed = []
end

here = fileparts(mfilename('fullpath'));
addpath(here); % DetectionBoxGUI + ExampleDetectionSelector must be reachable

if ~isempty(options.Seed), rng(options.Seed); end

if isempty(options.ProtocolFile)
    options.ProtocolFile = fullfile(here, 'DetectionExample.eprot');
end
if ~isfile(options.ProtocolFile)
    create_detection_protocol(options.ProtocolFile);
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

% --- Runtime scaffold: what RunExpt + ep_TimerFcn_Start normally do ------
RUNTIME = epsych.Runtime;
RUNTIME.isTest = true; % simulated observer: mark every DATA record as test data
RUNTIME.HELPER = epsych.Helper;
RUNTIME.Interfaces = P.Interfaces; % connects the hw.Software backend

% Dispatch assigns Values per trial, but read-back parameters need a live
% starting Value before the first DATA collection.
pResp = RUNTIME.find_parameter('RespCode');
pIn   = RUNTIME.find_parameter('InTrial');

subject = epsych.DefaultSubject(struct('Name', 'ExampleSubject', ...
    'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));
stamp = char(datetime('now', Format = 'yyMMdd''T''HHmmss'));
dataFile = fullfile(options.DataPath, sprintf('%s_%s.mat', subject.Name, stamp));

C = P.COMPILED;
T = struct;
T.protocol     = P;
T.Subject      = subject;
T.BoxID        = subject.BoxID;
T.parameters   = C.parameters;
T.trials       = C.trials;
T.writeparams  = C.writeparams;
idx = struct;
for k = 1:numel(C.writeparams)
    idx.(C.writeparams{k}) = k;
end
T.writeParamIdx = idx;
T.selector = epsych.TrialSelector.create(struct('trialFunc', C.OPTIONS.trialFunc));
T.selector.initialize(T);
T.FORCE_TRIAL          = false;
T.RECOMPILE_REQUESTED  = false;
T.DataFilename         = dataFile;
T.TrialIndex           = 1;
T.NextTrialID          = T.selector.selectNext(T);

T.selector.setRuntime(RUNTIME, 1);
RUNTIME.TRIALS = T; % the setter resolves CORE triggers and dispatches trial 1

% RunExpt launches the behavior GUI right after ep_TimerFcn_Start, then
% broadcasts the session mode; mirror that order here.
if options.ShowGUI
    DetectionBoxGUI(RUNTIME);
end
RUNTIME.HELPER.notify('ModeChange', ...
    epsych.eventModeChange(hw.DeviceState.Record));

% --- Trial loop ----------------------------------------------------------
lvlCol = idx.ToneLevel;
ttCol  = idx.TrialType;

for k = 1:options.NumTrials
    trialRow = RUNTIME.TRIALS(1).NextTrialID;
    lvl  = RUNTIME.TRIALS(1).trials{trialRow, lvlCol};
    isGo = RUNTIME.TRIALS(1).trials{trialRow, ttCol} == 0;

    setReadParameter(pIn, true);
    if options.TrialPause > 0, pause(options.TrialPause); end

    % Simulated observer: cumulative-Gaussian psychometric function on go
    % trials, a flat guess rate on catch trials.
    if isGo
        pHit = options.GuessRate + (1 - options.GuessRate - options.LapseRate) ...
            * normcdf((lvl - options.Threshold) / options.Slope);
        if rand < pHit
            bits = [epsych.BitMask.Hit, epsych.BitMask.Reward];
        else
            bits = epsych.BitMask.Miss;
        end
        bits(end+1) = epsych.BitMask.TrialType_0;
    else
        if rand < options.GuessRate
            bits = [epsych.BitMask.FalseAlarm, epsych.BitMask.Punish];
        else
            bits = epsych.BitMask.CorrectReject;
        end
        bits(end+1) = epsych.BitMask.TrialType_1;
    end
    rc = uint32(0);
    for b = bits(:).'
        rc = bitset(rc, uint32(b));
    end
    setReadParameter(pResp, double(rc));
    setReadParameter(pIn, false);

    % --- Trial completion, exactly as ep_TimerFcn_RunTime does it --------
    data = RUNTIME.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
    data.TrialIndex        = RUNTIME.TRIALS(1).TrialIndex;
    data.TrialID           = RUNTIME.TRIALS(1).NextTrialID;
    data.computerTimestamp = datetime('now');
    data.isTest            = RUNTIME.isTest;

    ti = RUNTIME.TRIALS(1).TrialIndex;
    if ti == 1
        RUNTIME.TRIALS(1).DATA = data;
    else
        RUNTIME.TRIALS(1).DATA(ti) = data;
    end

    RUNTIME.TRIALS(1).selector.onComplete(RUNTIME.TRIALS(1).NextTrialID, data);
    RUNTIME.HELPER.notify('NewData', epsych.TrialsData(RUNTIME.TRIALS(1)));

    RUNTIME.TRIALS(1).TrialIndex = ti + 1;
    if k < options.NumTrials
        RUNTIME.TRIALS(1).NextTrialID = ...
            RUNTIME.TRIALS(1).selector.selectNext(RUNTIME.TRIALS(1));
        RUNTIME.dispatchNextTrial(1);
    end
    drawnow limitrate
end

% --- Stop and save -------------------------------------------------------
RUNTIME.HELPER.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Stop));

% Same file layout as cl_SaveDataFcn: per-subject DATA plus repo metadata.
Data = RUNTIME.TRIALS(1).DATA;
Info = EPsychInfo().meta;
save(dataFile, 'Data', 'Info')
vprintf(0, 'Simulated session complete: %d trials saved to %s', numel(Data), dataFile)
vprintf(0, 'Next: explore_saved_data(''%s'')', dataFile)

if nargout == 0, clear RUNTIME; end
end


function setReadParameter(p, val)
% Rig-side write to a read-back parameter. Hardware backends refresh these
% from the device; hw.Software stores the Value directly, but Access='Read'
% blocks set.Value, so widen access for the write and restore it.
if isempty(p), return; end
ac = p.Access;
p.Access = 'Any';
p.Value = val;
p.Access = ac;
end
