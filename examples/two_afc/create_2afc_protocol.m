function P = create_2afc_protocol(filename, options)
% P = create_2afc_protocol(filename, Name=Value, ...)
% Build the two-alternative forced choice (2AFC) tutorial protocol in code
% and save it as a .eprot file.
%
% The task is a spatial brightness discrimination in which YOU are the
% subject: two lamps flash together, one brighter than the other, and you
% report which side was brighter — LEFT or RIGHT — with a button or an
% arrow key (TwoAFCBoxGUI, same folder). There is no "withhold" response;
% every trial demands a choice, which is what makes it forced choice.
%
% Parameters:
%   filename - Output path. Default: TwoAFC.eprot in this folder.
%
% Options:
%   Contrasts    - Brightness increments of the target lamp over the
%                  standard, in luminance units (default [0.04 0.08 0.16 0.32])
%   BaseLevel    - Luminance of the non-target lamp, 0-1 (default 0.35)
%   FlashDur     - How long both lamps are lit, ms (default 150)
%   ITIRange     - [min max] intertrial interval, redrawn per trial (default [800 1800])
%   RespWinDur   - How long the choice buttons stay armed, ms (default 3000)
%
% Returns:
%   P - The compiled epsych.Protocol.
%
% Try it:
%   create_2afc_protocol             % writes TwoAFC.eprot
%
% Walkthrough: https://github.com/dstolz/epsych2/wiki/Two-AFC-Task
%
% See also epsych.Protocol, TwoAFCBoxGUI, run_2afc_experiment

arguments
    filename (1,:) char = ''
    options.Contrasts (1,:) double {mustBePositive} = [0.04 0.08 0.16 0.32]
    options.BaseLevel (1,1) double {mustBeInRange(options.BaseLevel,0,1)} = 0.35
    options.FlashDur (1,1) double {mustBePositive} = 150
    options.ITIRange (1,2) double {mustBePositive} = [800 1800]
    options.RespWinDur (1,1) double {mustBePositive} = 3000
end

here = fileparts(mfilename('fullpath'));
if isempty(filename)
    filename = fullfile(here, 'TwoAFC.eprot');
end

P = epsych.Protocol(Info = 'Tutorial: two-alternative forced choice brightness discrimination');
sw = P.SoftwareModule;

% --- Conditions: a full factorial cross ----------------------------------
% Unlike the flash-detection tutorial, whose paired parameters advanced
% together, these two are left UNPAIRED — so the compiler crosses them,
% giving every side at every difficulty (2 x 4 = 8 conditions). That cross
% is the design: it counterbalances side against difficulty, so a subject
% who favours one hand cannot inflate performance at any one contrast.
%
% The name TrialType is not decorative: psychophysics.Detection reads a
% numeric TrialType field out of each DATA record to label trials, and
% teensy.Templates uses the same 0/1 convention for its 2AFC board
% program. Call it anything else and the analysis classes cannot see it.
sw.add_parameter('TrialType', [0 1], Type = 'Integer', ...
    Description = "Which lamp is brighter, i.e. which choice is correct: 0 = left, 1 = right");

sw.add_parameter('Contrast', options.Contrasts, ...
    Description = "Luminance increment of the brighter lamp over the standard; small = hard");

% --- Fixed stimulus and timing controls ----------------------------------
sw.add_parameter('BaseLevel', options.BaseLevel, ...
    Description = "Luminance of the dimmer (standard) lamp, 0-1");

sw.add_parameter('FlashDur', options.FlashDur, Unit = 'ms', ...
    Description = "How long both lamps are lit");

sw.add_parameter('RespWinDur', options.RespWinDur, Unit = 'ms', ...
    Description = "How long the choice remains available before the trial aborts");

p = sw.add_parameter('ITI', mean(options.ITIRange), Unit = 'ms', ...
    Description = "Intertrial interval, redrawn each trial");
p.Min = options.ITIRange(1);
p.Max = options.ITIRange(2);
p.isRandom = true;

% --- Read-back parameters ------------------------------------------------
% Access='Read' marks a parameter as rig-owned: excluded from compile and
% per-trial dispatch, collected into DATA at every trial end instead.
% Seed the Value first — set.Value refuses writes once Access='Read'.
p = sw.add_parameter('RespCode', 0, Type = 'Integer', ...
    Description = "epsych.BitMask response code, set by the behavior GUI at trial end");
p.Value = 0;
p.Access = 'Read';

% ChoiceSide is redundant with the Choice_0/Choice_1 bits inside RespCode,
% and recorded anyway: a rig reports what it knows, and a plain numeric
% column keeps the common analyses (P(chose right) against signed contrast)
% one line long.
%
% -1, not NaN, marks "no response". A parameter cannot hold NaN: every
% numeric write is clamped with max(value, Min) (hw.Parameter.clamp_value_)
% and MATLAB's max ignores NaN, so a NaN silently arrives as Min — -Inf by
% default. Any missing-data marker has to be a real number you choose.
p = sw.add_parameter('ChoiceSide', 0, Type = 'Integer', ...
    Description = "Side chosen: 0 = left, 1 = right, -1 = no response. Correct when it equals TrialType");
p.Value = -1;
p.Access = 'Read';

p = sw.add_parameter('RT_ms', 0, Unit = 'ms', ...
    Description = "Reaction time from response-window open; -1 when the trial aborted");
p.Value = -1;
p.Access = 'Read';

p = sw.add_parameter('InTrial', false, Type = 'Boolean', ...
    Description = "High while a trial is in progress");
p.Value = false;
p.Access = 'Read';

% --- Triggers ------------------------------------------------------------
% The runtime refuses to start without x_NewTrial_<BoxID>,
% x_ResetTrig_<BoxID>, and x_TrialComplete_<BoxID>. It polls
% x_TrialComplete_1.Value on every timer tick, so seed all three to 0 — an
% unset Value would make the first tick misread the trial as complete.
p = sw.add_parameter('x_NewTrial_1',      0, isTrigger = true); p.Value = 0;
p = sw.add_parameter('x_ResetTrig_1',     0, isTrigger = true); p.Value = 0;
p = sw.add_parameter('x_TrialComplete_1', 0, isTrigger = true); p.Value = 0;

% No Options.trialFunc: epsych.DefaultTrialSelector presents the
% least-used condition (random tie-break), which keeps all eight cells of
% the side x contrast design equally sampled without any custom code.

% --- Validate, compile, save ---------------------------------------------
% compile() does not throw on validation errors: it prints them and returns
% with COMPILED.ntrials == 0. Check validate() yourself for a clear report.
issues = P.validate();
for k = 1:numel(issues)
    vprintf(0, 1, 'Protocol issue (%s): %s', issues(k).field, issues(k).message)
end
assert(~any([issues.severity] == 2), 'Protocol has validation errors — not saving.')

P.compile();
assert(P.COMPILED.ntrials == 2 * numel(options.Contrasts), ...
    'Expected %d crossed conditions, compiled %d.', ...
    2 * numel(options.Contrasts), P.COMPILED.ntrials)
vprintf(0, 'Compiled %d conditions over parameters: %s', ...
    P.COMPILED.ntrials, strjoin(P.COMPILED.writeparams, ', '))

P.save(filename);

if nargout == 0, clear P; end
