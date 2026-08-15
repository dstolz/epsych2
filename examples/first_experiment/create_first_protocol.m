function P = create_first_protocol(filename, options)
% P = create_first_protocol(filename, Name=Value, ...)
% Build the "your first experiment" protocol in code and save it as a
% .eprot file. The same protocol could be built interactively in
% epsych.ProtocolDesigner; doing it in code makes every design decision
% explicit and reproducible.
%
% The task is a Go/No-Go flash detection in which YOU are the subject:
% on go trials the box GUI's stimulus lamp flashes for FlashDur ms; on
% catch trials nothing happens. Press RESPOND when you saw a flash,
% withhold when you did not (FirstExperimentBoxGUI, same folder).
%
% Parameters:
%   filename - Output path. Default: FirstExperiment.eprot in this folder.
%
% Options (all timing in ms; defaults suit a human subject):
%   FlashDurs    - Go-trial flash durations, one condition each (default [30 60 125 250])
%   ITIRange     - [min max] intertrial interval, redrawn per trial (default [1000 2500])
%   RespWinDelay - Trial onset to response-window open (default 400)
%   RespWinDur   - Response window duration (default 1500)
%
% Returns:
%   P - The compiled epsych.Protocol.
%
% Try it:
%   create_first_protocol            % writes FirstExperiment.eprot
%
% Walkthrough: https://github.com/dstolz/epsych2/wiki/Your-First-Experiment
%
% See also epsych.Protocol, FirstExperimentBoxGUI, run_first_experiment

arguments
    filename (1,:) char = ''
    options.FlashDurs (1,:) double {mustBePositive} = [30 60 125 250]
    options.ITIRange (1,2) double {mustBePositive} = [1000 2500]
    options.RespWinDelay (1,1) double {mustBeNonnegative} = 400
    options.RespWinDur (1,1) double {mustBePositive} = 1500
end

here = fileparts(mfilename('fullpath'));
if isempty(filename)
    filename = fullfile(here, 'FirstExperiment.eprot');
end

% A new Protocol already owns a connected hw.Software interface
% (P.SoftwareModule); for a hardware-free task no other interface is needed.
P = epsych.Protocol(Info = 'Tutorial: Go/No-Go flash detection with a human subject');
sw = P.SoftwareModule;

% --- Stimulus conditions -------------------------------------------------
% A multi-element value list defines the levels a parameter steps through.
% Unpaired parameters are fully crossed at compile time; sharing a
% UserData.Pair group makes parameters advance together instead, so these
% two lists define one condition per flash duration plus one silent catch.
nGo = numel(options.FlashDurs);
sw.add_parameter('TrialType', [zeros(1,nGo) 1], Type = 'Integer', ...
    Description = "0 = flash (go), 1 = silent catch (no-go)", ...
    UserData = struct('Pair', 'StimCondition'));

sw.add_parameter('FlashDur', [options.FlashDurs 0], Unit = 'ms', ...
    Description = "Lamp flash duration; 0 on catch trials (no flash)", ...
    UserData = struct('Pair', 'StimCondition'));

% --- Timing controls -----------------------------------------------------
% Single-value writable parameters are dispatched every trial but do not
% expand the condition list. The operator can edit them live from the GUI.
% isRandom redraws the value uniformly in [Min, Max] on every dispatch.
p = sw.add_parameter('ITI', mean(options.ITIRange), Unit = 'ms', ...
    Description = "Intertrial interval, redrawn each trial");
p.Min = options.ITIRange(1);
p.Max = options.ITIRange(2);
p.isRandom = true;

sw.add_parameter('RespWinDelay', options.RespWinDelay, Unit = 'ms', ...
    Description = "Response window opens this long after trial onset (fixed for all trials, so the timing never reveals a catch trial)");

sw.add_parameter('RespWinDur', options.RespWinDur, Unit = 'ms', ...
    Description = "How long the RESPOND button stays armed");

% --- Read-back parameters ------------------------------------------------
% Access='Read' excludes a parameter from compile and per-trial dispatch;
% instead its Value is collected into DATA at every trial end. RespCode is
% the conventional field name the analysis tools (psychophysics.Detection)
% look for: an epsych.BitMask-encoded outcome set by the rig — here, by
% the box GUI acting as the rig — at trial end.
% set.Value refuses writes once Access='Read', so seed the Value first.
p = sw.add_parameter('RespCode', 0, Type = 'Integer', ...
    Description = "epsych.BitMask response code, set by the box GUI at trial end");
p.Value = 0;
p.Access = 'Read';

p = sw.add_parameter('RT_ms', 0, Unit = 'ms', ...
    Description = "Reaction time from response-window open; NaN when no response");
p.Value = NaN;
p.Access = 'Read';

p = sw.add_parameter('InTrial', false, Type = 'Boolean', ...
    Description = "High while a trial is in progress");
p.Value = false;
p.Access = 'Read';

% --- Triggers ------------------------------------------------------------
% Every protocol needs the three core triggers x_NewTrial_<BoxID>,
% x_ResetTrig_<BoxID>, x_TrialComplete_<BoxID>; the runtime refuses to
% start without them (epsych.Runtime.resolveCoreParameters). On TDT
% hardware these are RPvds tags; on a software rig they are plain trigger
% parameters. The runtime polls x_TrialComplete_1.Value on every timer
% tick, so seed it (and its siblings) to 0 — an unset Value would make the
% very first tick misread the trial as complete.
p = sw.add_parameter('x_NewTrial_1',      0, isTrigger = true); p.Value = 0;
p = sw.add_parameter('x_ResetTrig_1',     0, isTrigger = true); p.Value = 0;
p = sw.add_parameter('x_TrialComplete_1', 0, isTrigger = true); p.Value = 0;

% No Options.trialFunc: trial selection falls back to
% epsych.DefaultTrialSelector (least-presented condition, random ties).

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
