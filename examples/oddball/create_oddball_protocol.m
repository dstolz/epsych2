function P = create_oddball_protocol(filename, options)
% P = create_oddball_protocol(filename, Name=Value, ...)
% Build the auditory oddball example protocol in code and save it as a
% .eprot file.
%
% The task: a stream of sounds, most of them STANDARDS, occasionally a
% DEVIANT. Press RESPOND (or the space bar) when you hear a deviant; let the
% standards go by. Every sound is one trial, so every sound is scored:
%
%                  respond          withhold
%   deviant        Hit              Miss
%   standard       False Alarm      Correct Reject
%
% That is a Go/No-Go detection in EPsych's terms -- deviants are the
% stimulus (TrialType 0), standards the catch trials (TrialType 1) -- so the
% stock detection analyses (psychophysics.Detection, gui.components.SessionPerformance,
% the sliding-window and psychometric plots) apply unchanged.
%
% The SEQUENCE is the trial selector's job (OddballSelector, same folder):
% each deviant follows a run of MinStandards..MaxStandards standards, the
% run length drawn block-randomized, and each sound is drawn
% block-randomized from its bank. This protocol only declares the knobs.
%
% Parameters:
%   filename - Output path. Default: Oddball.eprot in this folder.
%
% Options:
%   StandardFiles - .wav files the standards are drawn from (default: the
%                   tones make_oddball_sounds generates)
%   DeviantFiles  - .wav files the deviants are drawn from (default: the
%                   glides make_oddball_sounds generates)
%   MinStandards  - Fewest standards before a deviant (default 1)
%   MaxStandards  - Most standards before a deviant (default 6)
%   ITIRange      - [min max] silent interval before each sound, ms,
%                   redrawn every trial (default [800 1500])
%   RespWinDelay  - Response window opens this long after sound onset, ms
%                   (default 100: faster than any response to the sound)
%   RespWinDur    - How long the response window stays open, ms (default 1200)
%
% Returns:
%   P - The compiled epsych.Protocol.
%
% Try it:
%   create_oddball_protocol                  % writes Oddball.eprot
%   create_oddball_protocol('', MaxStandards = 10, RespWinDur = 900)
%
% See also OddballSelector, OddballBehaviorGUI, run_oddball_experiment,
%   make_oddball_sounds

arguments
    filename (1,:) char = ''
    options.StandardFiles (1,:) string = string.empty(1,0)
    options.DeviantFiles (1,:) string = string.empty(1,0)
    options.MinStandards (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    options.MaxStandards (1,1) double {mustBeInteger, mustBePositive} = 6
    options.ITIRange (1,2) double {mustBePositive} = [800 1500]
    options.RespWinDelay (1,1) double {mustBeNonnegative} = 100
    options.RespWinDur (1,1) double {mustBePositive} = 1200
end

here = fileparts(mfilename('fullpath'));
addpath(here); % OddballSelector must resolve when the protocol validates

if isempty(filename)
    filename = fullfile(here, 'Oddball.eprot');
end

assert(options.MinStandards <= options.MaxStandards, ...
    'MinStandards (%d) must not exceed MaxStandards (%d).', ...
    options.MinStandards, options.MaxStandards)
assert(options.ITIRange(1) <= options.ITIRange(2), 'ITIRange must be [min max].')

if isempty(options.StandardFiles) || isempty(options.DeviantFiles)
    [stdFiles, devFiles] = make_oddball_sounds();
    if isempty(options.StandardFiles), options.StandardFiles = stdFiles; end
    if isempty(options.DeviantFiles),  options.DeviantFiles  = devFiles; end
end
stdFiles = checkWavFiles(options.StandardFiles, 'StandardFiles');
devFiles = checkWavFiles(options.DeviantFiles, 'DeviantFiles');

P = epsych.Protocol(Info = 'Example: auditory oddball detection (block-randomized standards and deviants)');
sw = P.SoftwareModule;

% --- The one condition: which kind of sound ------------------------------
% Two rows, nothing crossed with them. OddballSelector picks the row; the
% sound itself is not a condition, because the banks can change mid-session
% and a condition list can only change by recompiling. TrialType 0 is the
% stimulus and 1 the catch trial because that is what
% psychophysics.Detection expects by default (StimulusTrialType / CatchTrialType).
sw.add_parameter('TrialType', [0 1], Type = 'Integer', ...
    Description = "0 = deviant (respond), 1 = standard (withhold). Chosen by OddballSelector");

% --- Trial structure -----------------------------------------------------
% Single-level writable parameters: one column each in the trial table,
% dispatched every trial, editable live from the behavior GUI, and recorded
% in every DATA record -- so the record says what the range WAS on each
% trial even when the operator changed it part way through.
p = sw.add_parameter('MinStandards', options.MinStandards, Type = 'Integer', ...
    Description = "Fewest standards before a deviant (block-randomized between Min and Max)");
p.Min = 0; p.Max = 50;
p = sw.add_parameter('MaxStandards', options.MaxStandards, Type = 'Integer', ...
    Description = "Most standards before a deviant (block-randomized between Min and Max)");
p.Min = 0; p.Max = 50;

% isRandom redraws randi([Min Max]) on every dispatch; the behavior GUI edits
% Min and Max together with one range control.
p = sw.add_parameter('ITI', mean(options.ITIRange), Unit = 'ms', ...
    Description = "Silent interval before each sound, redrawn each trial between Min and Max");
p.Min = options.ITIRange(1);
p.Max = options.ITIRange(2);
p.isRandom = true;

sw.add_parameter('RespWinDelay', options.RespWinDelay, Unit = 'ms', ...
    Description = "Response window opens this long after sound onset");
sw.add_parameter('RespWinDur', options.RespWinDur, Unit = 'ms', ...
    Description = "How long the response window stays open");

% --- Sound banks: session configuration, not trial data ------------------
% Visible = false keeps a parameter out of the trial table AND out of DATA
% (epsych.Protocol.compile_internal and ep_TimerFcn_RunTime both filter on
% it), which is right for a list of files: it is configuration the operator
% sets, and each trial records the ONE file it played in StimFile instead.
% The value is the whole list, so Values holds one level -- a cell inside
% the cell. Value is seeded too, because add_parameter fills only Values and
% an invisible parameter is never dispatched.
p = sw.add_parameter('StandardFiles', {cellstr(stdFiles)}, Type = 'File', Visible = false, ...
    Description = "Bank of .wav files the standards are drawn from, block-randomized");
p.Value = cellstr(stdFiles);
p = sw.add_parameter('DeviantFiles', {cellstr(devFiles)}, Type = 'File', Visible = false, ...
    Description = "Bank of .wav files the deviants are drawn from, block-randomized");
p.Value = cellstr(devFiles);

% --- Read-back parameters: what each trial did ---------------------------
% Access='Read': out of the trial table, into DATA at every trial end.
% OddballSelector writes the first four as it selects each trial, so they
% are already set when the trial is dispatched; the behavior GUI (standing in
% for the rig) writes the rest when it scores the trial. Seed each Value
% before the access change, since set.Value refuses writes to a Read
% parameter. -1 rather than NaN marks "none": a numeric write is clamped
% with max(value, Min), and max ignores NaN.
p = sw.add_parameter('StimFile', '', Type = 'File', ...
    Description = "The .wav file played on this trial");
p.Value = ''; p.Access = 'Read';

p = sw.add_parameter('StimID', 0, Type = 'Integer', ...
    Description = "Position of StimFile in its bank (StandardFiles or DeviantFiles)");
p.Value = 0; p.Access = 'Read';

p = sw.add_parameter('RunLength', 0, Type = 'Integer', ...
    Description = "Standards in this trial's run, i.e. how many standards preceded the deviant that ends it");
p.Value = 0; p.Access = 'Read';

p = sw.add_parameter('RunPosition', 0, Type = 'Integer', ...
    Description = "Position in the run: 1..RunLength for a standard, RunLength+1 for the deviant");
p.Value = 0; p.Access = 'Read';

p = sw.add_parameter('RespCode', 0, Type = 'Integer', ...
    Description = "epsych.BitMask response code, set by the behavior GUI at trial end");
p.Value = 0; p.Access = 'Read';

p = sw.add_parameter('RT_ms', 0, Unit = 'ms', ...
    Description = "Reaction time from sound onset; -1 when there was no response");
p.Value = -1; p.Access = 'Read';

p = sw.add_parameter('InTrial', false, Type = 'Boolean', ...
    Description = "High while a trial is in progress");
p.Value = false; p.Access = 'Read';

% --- Triggers ------------------------------------------------------------
% The runtime refuses to start without these three, and polls
% x_TrialComplete_1.Value on every timer tick -- seed all three to 0, or the
% first tick reads an empty value as "complete".
p = sw.add_parameter('x_NewTrial_1',      0, isTrigger = true); p.Value = 0;
p = sw.add_parameter('x_ResetTrig_1',     0, isTrigger = true); p.Value = 0;
p = sw.add_parameter('x_TrialComplete_1', 0, isTrigger = true); p.Value = 0;

% --- Trial selection -----------------------------------------------------
P.setOption('trialFunc', 'OddballSelector');

% --- Validate, compile, save ---------------------------------------------
% compile() does not throw on validation errors: it reports them and
% compiles nothing. Check validate() for a clear report.
issues = P.validate();
for k = 1:numel(issues)
    vprintf(0, 1, 'Protocol issue (%s): %s', issues(k).field, issues(k).message)
end
assert(~any([issues.severity] == 2), 'Protocol has validation errors - not saving.')

P.compile();
assert(P.COMPILED.ntrials == 2, 'Expected 2 conditions (deviant, standard), compiled %d.', ...
    P.COMPILED.ntrials)
vprintf(0, 'Compiled %d conditions over parameters: %s', ...
    P.COMPILED.ntrials, strjoin(P.COMPILED.writeparams, ', '))

P.save(filename);

if nargout == 0, clear P; end
end


function files = checkWavFiles(files, label)
% Absolute, existing, readable audio files -- refused here rather than at
% the first trial that tries to play one.
files = string(files(:)).';
assert(~isempty(files), '%s is empty.', label)
for k = 1:numel(files)
    f = char(files(k));
    if ~isfile(f)
        error('create_oddball_protocol:FileNotFound', '%s: no such file "%s".', label, f)
    end
    [~, attr] = fileattrib(f); % Name is the absolute path
    f = attr.Name;
    try
        audioinfo(f);
    catch ME
        error('create_oddball_protocol:NotAudio', '%s: "%s" is not a readable audio file (%s).', ...
            label, f, ME.message)
    end
    files(k) = f;
end
end
