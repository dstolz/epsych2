function specs = parameterSpecs(obj)
% specs = parameterSpecs(obj)
% Describe the hw.Parameter set this program needs on its interface.
%
% Returns descriptions rather than live parameters so the designer can preview
% the parameter table with no hardware and no hw.Module, and so the whole
% mapping can be tested headlessly. applyToModule turns these into real
% parameters.
%
% The names here are not arbitrary. epsych.Runtime.resolveTriggerParameters looks
% up x_NewTrial_<BoxID>, x_ResetTrig_<BoxID> and x_TrialComplete_<BoxID>
% literally and aborts the run if any is missing; gui.components.OnlinePlot looks up
% _TrigState~<BoxID> and _TrialNum~<BoxID> literally; gui.components.History requires
% RespCode; and psychophysics.Detection reads RespCode plus a separate integer
% TrialType. Emitting all of them is what makes a Teensy protocol light up the
% shipped GUIs with no extra wiring.
%
% Triggers use Access='Any', never 'Write'. hw.Interface.all_parameters treats
% 'Write' as excluded from a 'Read' filter, so resolveTriggerParameters would not
% find a 'Write' trigger and the run would abort with MissingTrigger.
%
% Returns:
%   specs - 1xN struct array with fields:
%       Name             - char name for hw.Module.add_parameter
%       Value            - initial value (lands in Values, not Value)
%       Options          - struct of add_parameter name-value options
%       UpdateEveryTrial - logical to assign after creation
%       Origin           - "core" | "variable" | "channel" | "counter"
%       Description      - one-line summary for the preview table
%
% Example
%   specs = program.parameterSpecs();
%   disp(string({specs.Name})')
%
% See also: teensy.Program.applyToModule, epsych.Runtime, gui.components.OnlinePlot

arguments
    obj (1,1) teensy.Program
end

box = obj.BoxID;
specs = localSpec_();

% --- Core triggers --------------------------------------------------------
% isTrigger=true also sets UpdateEveryTrial=false, which is what keeps a
% trigger out of the per-trial parameter dispatch; it is stated explicitly
% here so the intent survives a change to that setter.

specs(end+1) = localSpec_(sprintf('x_NewTrial_%d', box), 0, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'isTrigger', true), false, ...
    "core", "Pulsed by the runtime to start a trial.");

specs(end+1) = localSpec_(sprintf('x_ResetTrig_%d', box), 0, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'isTrigger', true), false, ...
    "core", "Pulsed before each trial; clears TrialComplete, latches and the event log.");

specs(end+1) = localSpec_(sprintf('x_TrialComplete_%d', box), 0, ...
    struct('Type', 'Boolean', 'Access', 'Read'), false, ...
    "core", "Raised by the board when a terminal state is entered.");

% --- Trial results --------------------------------------------------------

specs(end+1) = localSpec_('RespCode', 0, ...
    struct('Type', 'Integer', 'Access', 'Read', ...
        'Description', "epsych.BitMask outcome bits for the completed trial."), ...
    false, "core", "Outcome bitmask; decoded by epsych.BitMask.decode.");

specs(end+1) = localSpec_('RespLatency', 0, ...
    struct('Type', 'Float', 'Access', 'Read', 'Unit', 'ms'), false, ...
    "core", "Milliseconds from trial start to the Mark Latency action.");

specs(end+1) = localSpec_('TrialType', 0, ...
    struct('Type', 'Integer', 'Access', 'Read'), false, ...
    "core", "Integer trial type; psychophysics.Detection reads this, not RespCode.");

specs(end+1) = localSpec_('InTrial', 0, ...
    struct('Type', 'Boolean', 'Access', 'Read'), false, ...
    "core", "True while a trial is running.");

specs(end+1) = localSpec_('StateIndex', 0, ...
    struct('Type', 'Integer', 'Access', 'Read'), false, ...
    "core", "Index of the state the board is currently in; drives the live monitor.");

% --- gui.components.OnlinePlot literals ---------------------------------------------
% The ~<BoxID> suffix form differs from the x_*_<BoxID> trigger form. That is
% not a typo: OnlinePlot looks these two names up exactly as written.

specs(end+1) = localSpec_(sprintf('_TrigState~%d', box), 0, ...
    struct('Type', 'Boolean', 'Access', 'Read', 'Visible', false), false, ...
    "core", "Trial-state flag polled by gui.components.OnlinePlot.");

specs(end+1) = localSpec_(sprintf('_TrialNum~%d', box), 0, ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', false), false, ...
    "core", "Trial counter polled by gui.components.OnlinePlot.");

% --- Program variables ----------------------------------------------------

for i = 1:numel(obj.Variables)
    v = obj.Variables(i);
    spec = v.toParameterSpec();

    description = v.Description;
    if strlength(description) == 0
        description = sprintf("Program variable (%s).", v.Type);
    end

    specs(end+1) = localSpec_(spec.Name, spec.Value, spec.Options, ...
        spec.UpdateEveryTrial, "variable", description);
end

% --- Channel state --------------------------------------------------------
% One readable parameter per channel, so the per-trial DATA record carries
% what each sensor and each output was doing without needing the event log.
%
% Outputs are included as well as inputs. That is what lets a state drive a
% named output purely as a phase flag -- a "RespWindow" output held high for
% the duration of the response window shows up as a readable RespWindow
% parameter, which is exactly what gui.components.Parameter_Monitor renders as a lamp.

for i = 1:numel(obj.Channels)
    c = obj.Channels(i);

    if c.Kind == "Digital"
        options = struct('Type', 'Boolean', 'Access', 'Read');
        description = sprintf("State of digital %s '%s'.", lower(c.Direction), c.Name);
    else
        options = struct('Type', 'Float', 'Access', 'Read', 'Unit', char(c.Units));
        description = sprintf("Value of analog %s '%s'.", lower(c.Direction), c.Name);
    end

    specs(end+1) = localSpec_(char(c.Name), 0, options, false, "channel", description);
end

% --- Counters -------------------------------------------------------------

for i = 1:numel(obj.Counters)
    name = obj.Counters(i).Name;
    specs(end+1) = localSpec_(char(name), 0, ...
        struct('Type', 'Integer', 'Access', 'Read'), false, "counter", ...
        sprintf("Edge count on '%s' for the completed trial.", obj.Counters(i).Channel));
end
end


function s = localSpec_(name, value, options, updateEveryTrial, origin, description)
% s = localSpec_(...)
% Build one spec, or the empty spec array when called with no arguments.
%
% Fixed field order so specs from different sources always concatenate.
fields = {'Name', 'Value', 'Options', 'UpdateEveryTrial', 'Origin', 'Description'};

if nargin == 0
    args = [fields; repmat({{}}, 1, numel(fields))];
    s = struct(args{:});
    return
end

s = struct( ...
    'Name', char(name), ...
    'Value', value, ...
    'Options', options, ...
    'UpdateEveryTrial', logical(updateEveryTrial), ...
    'Origin', string(origin), ...
    'Description', string(description));
end
