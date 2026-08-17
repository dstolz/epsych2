function P = create_detection_protocol(filename)
% P = create_detection_protocol(filename)
% Build the worked-example tone detection protocol entirely in code and save
% it as a .eprot file. The same protocol could be built interactively in
% epsych.ProtocolDesigner; doing it in code makes every design decision
% explicit and reproducible.
%
% The task is a Go/No-Go tone detection: on go trials a tone is presented at
% one of five levels; on silent catch trials the animal should withhold.
% Trial selection is handled by ExampleDetectionSelector (same folder).
%
% Parameters:
%   filename - Output path. Default: DetectionExample.eprot in this folder.
%
% Returns:
%   P - The compiled epsych.Protocol.
%
% Try it:
%   create_detection_protocol            % writes DetectionExample.eprot
%
% Walkthrough: documentation/examples/Detection_Task_1_Protocol.md
%
% See also epsych.Protocol, ExampleDetectionSelector, run_detection_session

arguments
    filename (1,:) char = ''
end

here = fileparts(mfilename('fullpath'));
addpath(here); % ExampleDetectionSelector must be resolvable when the protocol validates

if isempty(filename)
    filename = fullfile(here, 'DetectionExample.eprot');
end

% A new Protocol already owns a connected hw.Software interface
% (P.SoftwareModule); for a simulated task no other interface is needed.
P = epsych.Protocol(Info = 'Worked example: simulated Go/No-Go tone detection');
sw = P.SoftwareModule;

% --- Stimulus conditions -------------------------------------------------
% A multi-element value list defines the levels a parameter steps through.
% Unpaired parameters are fully crossed at compile time; sharing a
% UserData.Pair group makes parameters advance together instead, so these
% two lists define 6 conditions (5 go levels + 1 silent catch), not 12.
sw.add_parameter('TrialType', [0 0 0 0 0 1], Type = 'Integer', ...
    Description = "0 = tone (go), 1 = silent catch (no-go)", ...
    UserData = struct('Pair', 'StimCondition'));

sw.add_parameter('ToneLevel', [20 30 40 50 60 0], Unit = 'dB SPL', ...
    Description = "Tone level; 0 on catch trials (no tone is presented)", ...
    UserData = struct('Pair', 'StimCondition'));

% --- Fixed stimulus and timing controls ----------------------------------
% Single-value writable parameters are dispatched every trial but do not
% expand the condition list. The operator can edit them live from the behavior GUI.
sw.add_parameter('ToneFreq',  4000, Unit = 'Hz');
sw.add_parameter('ToneDur',    500, Unit = 'ms');
sw.add_parameter('RewardVol',   25, Unit = 'uL');

% isRandom redraws the value uniformly in [Min, Max] on every dispatch.
p = sw.add_parameter('ITI', 3000, Unit = 'ms', ...
    Description = "Intertrial interval, redrawn each trial");
p.Min = 2000;
p.Max = 4000;
p.isRandom = true;

% An Expression re-evaluates against sibling parameters on every dispatch,
% after the parameters it references (dependency-ordered dispatch).
p = sw.add_parameter('RespWinDelay', 0, Unit = 'ms', ...
    Description = "Response window opens this long after trial onset");
p.Expression = "ToneDur + 250";

% --- Read-back parameters ------------------------------------------------
% Access='Read' excludes a parameter from compile and per-trial dispatch;
% instead its Value is collected into DATA at every trial end. RespCode is
% the conventional field name the analysis tools (psychophysics.Detection)
% look for: an epsych.BitMask-encoded outcome the rig sets at trial end.
% set.Value refuses writes once Access='Read', so seed the Value first.
p = sw.add_parameter('RespCode', 0, Type = 'Integer', ...
    Description = "epsych.BitMask response code, set by the rig at trial end");
p.Value = 0;
p.Access = 'Read';

% -1, not NaN, marks "no response" (Miss or CorrectReject): a parameter
% cannot hold NaN, since every numeric write is clamped with
% max(value, Min) and MATLAB's max ignores NaN (hw.Parameter.clamp_value_).
p = sw.add_parameter('RT_ms', 0, Unit = 'ms', ...
    Description = "Reaction time from tone onset; -1 when no response was made");
p.Value = -1;
p.Access = 'Read';

p = sw.add_parameter('InTrial', false, Type = 'Boolean', ...
    Description = "High while a trial is in progress");
p.Value = false;
p.Access = 'Read';

% --- Triggers ------------------------------------------------------------
% Every protocol needs the three core triggers x_NewTrial_<BoxID>,
% x_ResetTrig_<BoxID>, x_TrialComplete_<BoxID>; the runtime refuses to start
% without them (epsych.Runtime.resolveTriggerParameters). On TDT hardware these
% are RPvds tags; on a software rig they are plain trigger parameters.
sw.add_parameter('x_NewTrial_1',      0, isTrigger = true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger = true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger = true);

% Extra trigger for the behavior GUI's manual reward button.
sw.add_parameter('Reward', 0, isTrigger = true, ...
    Description = "Manually deliver one reward");

% --- Trial selection policy ----------------------------------------------
% Options.trialFunc names an epsych.TrialSelector subclass (a class, not a
% function). Empty means epsych.DefaultTrialSelector.
P.setOption('trialFunc', 'ExampleDetectionSelector');

% --- Validate, compile, save ---------------------------------------------
% compile() does not throw on validation errors: it prints them and returns
% with COMPILED.ntrials == 0. Check validate() yourself for a clear report.
issues = P.validate();
for k = 1:numel(issues)
    vprintf(0, 1, 'Protocol issue (%s): %s', issues(k).field, issues(k).message)
end
assert(~any([issues.severity] == 2), 'Protocol has validation errors — not saving.')

P.compile();
assert(P.COMPILED.ntrials > 0, 'Compile produced no trials.')
vprintf(0, 'Compiled %d conditions over parameters: %s', ...
    P.COMPILED.ntrials, strjoin(P.COMPILED.writeparams, ', '))

P.save(filename);

if nargout == 0, clear P; end
