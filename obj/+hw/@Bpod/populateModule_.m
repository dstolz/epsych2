function populateModule_(obj, module, options)
% populateModule_(obj, module)
% populateModule_(obj, module, Mode='replace')
% Build the fixed hw.Parameter table for a Bpod state machine on `module`.
%
% Bpod 0.5/0.6 has no descriptor opcode. Unlike hw.Teensy, the firmware cannot
% be asked what it exposes, so this table is a literal transcription of the
% board (8 behavior ports with an IR beam and an LED each, 2 BNC in / 2 BNC
% out, 4 wire in / 4 wire out, 8 valves, 2 hardware serial channels) plus the
% fixed per-trial record hw.Bpod assembles from the event stream. Nothing here
% touches the serial port: the whole table is built offline by ProtocolDesigner
% and by a protocol restored from disk, with no board attached.
%
% VISIBLE / ACCESS MATRIX
% This is the least obvious part of the file. Two shipped consumers read the
% same table through two different filters, so flipping a Visible flag silently
% moves a parameter between them rather than producing an error:
%
%   trial table = Visible == true && Access ~= 'Read'
%                 (epsych.Protocol.compile_internal, the Visible/Access guards)
%   DATA sweep  = all_parameters(Access='Read'), whose defaults are
%                 includeInvisible=false and includeTriggers=false, i.e.
%                 Visible == true && ~isTrigger && Access ~= 'Write'
%                 (ep_TimerFcn_RunTime, the per-trial `data = ...` line)
%
% Therefore, in this file:
%   Visible=false                -> operator-facing only. Never compiled into a
%                                   trial, never written into DATA. Every
%                                   immediate I/O line, both serial channels,
%                                   all 14 inputs, the three x_*_<Box> trial
%                                   triggers, and the two gui.OnlinePlot
%                                   literals live here; they move only through
%                                   explicit set_parameter / trigger calls.
%   Visible=true,  Access='Any'  -> trial CONFIG. A column of the trial table
%                                   AND a field of DATA.
%   Visible=true,  Access='Read' -> trial RESULT. A field of DATA only; the
%                                   'Read' access is what keeps it out of the
%                                   trial table.
%
% The trial-result block is a FROZEN field set. The runtime stores each trial
% with `RUNTIME.TRIALS(i).DATA(k) = data`, which throws "Subscripted assignment
% between dissimilar structures" the moment one trial reports a different set of
% fields than another. Every result parameter must therefore exist on every
% trial and report NaN/0 when the matrix never visited the state that would have
% produced it. Results are never added or removed to match what a trial happened
% to do, and no Min is placed on a result so that a NaN sentinel cannot be
% clamped to 0.
%
% Parameters:
%   obj          - hw.Bpod instance that owns the module.
%   module       - hw.Module to populate.
%   options.Mode - 'merge' (default) adds only parameters whose hardware name is
%                  not already on the module, leaving every existing
%                  hw.Parameter handle - and the trial levels an operator
%                  authored into it - untouched. That is what makes
%                  setup_interface safe to run on every reconnect and what lets
%                  a restored protocol keep its authored levels. 'replace'
%                  discards module.Parameters and rebuilds the table from
%                  scratch.
%
% See also: hw.Bpod.setup_interface, hw.Bpod.get_parameter,
%           hw.Teensy.populateModuleParametersFromDescriptor,
%           teensy.Program.parameterSpecs, epsych.BitMask

arguments
    obj
    module (1,1) hw.Module
    options.Mode (1,:) char {mustBeMember(options.Mode, {'merge', 'replace'})} = 'merge'
end

if strcmp(options.Mode, 'replace')
    module.Parameters = hw.Parameter.empty(1, 0);
    existingNames = {};
else
    % Match on the hardware name, not on Name: ensureUniqueParameterNames
    % rewrites Name on a collision, and merging against Name would then add a
    % second copy of a parameter that is already present.
    existingNames = arrayfun(@hw.Interface.getHardwareParameterName, ...
        module.Parameters, UniformOutput = false);
end

specs = local_parameterSpecs_(obj.BoxID);

nAdded = 0;
nSkipped = 0;
for k = 1:numel(specs)
    name = specs(k).Name;

    if ismember(name, existingNames)
        nSkipped = nSkipped + 1;
        continue
    end

    nv = namedargs2cell(specs(k).Options);
    P = module.add_parameter(name, specs(k).Value, nv{:});

    % Wire dispatch in set_parameter/get_parameter/trigger resolves the
    % hardware name, so a later rename by ensureUniqueParameterNames changes
    % only what the GUI shows.
    obj.setHardwareParameterName(P, name);

    existingNames{end + 1} = name;
    nAdded = nAdded + 1;
end

% Harmless when the module is not yet attached to obj.Module (the array is
% empty and the method returns immediately); cheap insurance when it is.
obj.ensureUniqueParameterNames();

vprintf(2, 'Bpod: module "%s" holds %d parameter(s) (%d added, %d already present, mode=%s)', ...
    module.Name, numel(module.Parameters), nAdded, nSkipped, options.Mode);

end


function specs = local_parameterSpecs_(B)
% specs = local_parameterSpecs_(B)
% Describe every parameter a Bpod interface exposes for box B.
%
% Returned as descriptions rather than live hw.Parameter objects so the table
% can be reordered or previewed without a module, and so the merge loop above
% has exactly one place to apply its idempotency rule.
%
% Returns:
%   specs - 1xN struct array with fields Name, Value, and Options (a scalar
%           struct of hw.Module.add_parameter name-value options).

specs = local_spec_();

% --- Immediate outputs ---------------------------------------------------
% Invisible and Access='Any': operator-facing lines driven by set_parameter,
% deliberately kept out of both the trial table and the DATA sweep.
%
% hw.Bpod keeps an absolute shadow of these (valves_, pwm_, bncOut_, wireOut_)
% and always emits a full mask. Bpod's own ManualOverride is toggle-based and
% would drift out of step with the table after any missed write.

for i = 1:8
    specs(end + 1) = local_spec_(sprintf('Valve%d', i), false, ...
        struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, ...
               'Min', 0, 'Max', 1, ...
               'Description', sprintf("Solenoid valve %d. Absolute state; the full O-V valve mask is re-emitted on every write.", i)));
end

for i = 1:8
    specs(end + 1) = local_spec_(sprintf('PWM%d', i), 0, ...
        struct('Type', 'Integer', 'Access', 'Any', 'Visible', false, ...
               'Min', 0, 'Max', 255, ...
               'Description', sprintf("Port %d LED brightness, 0-255. Sent as byte %d of the 8-byte O-P PWM payload.", i, i)));
end

for i = 1:2
    specs(end + 1) = local_spec_(sprintf('BNCOut%d', i), false, ...
        struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, ...
               'Description', sprintf("BNC output %d TTL level. Absolute state; the full O-B mask is re-emitted on every write.", i)));
end

for i = 1:4
    specs(end + 1) = local_spec_(sprintf('WireOut%d', i), false, ...
        struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, ...
               'Description', sprintf("Wire output %d TTL level. Absolute state; the full O-W mask is re-emitted on every write.", i)));
end

% --- Hardware serial channels --------------------------------------------
% Access='Write' because there is nothing to read back: the byte is handed to
% the UART and forgotten. 'Write' also excludes them from the DATA sweep on its
% own, independently of Visible.

for ch = 1:2
    specs(end + 1) = local_spec_(sprintf('Serial%dByte', ch), 0, ...
        struct('Type', 'Integer', 'Access', 'Write', 'Visible', false, ...
               'Min', 0, 'Max', 255, ...
               'Description', sprintf("Momentary. Writing emits ['H' %d byte] on hardware serial channel %d and retains nothing.", ch, ch)));
end

% --- Immediate inputs ----------------------------------------------------
% Access='Read' and invisible. hw.Bpod serves these from its snapshot cache:
% the 'I' opcode answers with a bare, unframed byte, so it must never be issued
% while a matrix is running or the reply would be parsed as an opcode.

for i = 1:8
    specs(end + 1) = local_spec_(sprintf('Port%dIn', i), false, ...
        struct('Type', 'Boolean', 'Access', 'Read', 'Visible', false, ...
               'Description', sprintf("Port %d IR beam. The firmware line is INPUT_PULLUP, so the raw byte is inverted here: true means the beam is broken.", i)));
end

for i = 1:2
    specs(end + 1) = local_spec_(sprintf('BNCIn%d', i), false, ...
        struct('Type', 'Boolean', 'Access', 'Read', 'Visible', false, ...
               'Description', sprintf("BNC input %d TTL level.", i)));
end

for i = 1:4
    specs(end + 1) = local_spec_(sprintf('WireIn%d', i), false, ...
        struct('Type', 'Boolean', 'Access', 'Read', 'Visible', false, ...
               'Description', sprintf("Wire input %d TTL level.", i)));
end

% --- Trial control -------------------------------------------------------
% epsych.Runtime.resolveCoreParameters looks these three names up literally as
% x_<NewTrial|ResetTrig|TrialComplete>_<BoxID> and aborts the run if any is
% missing. Access is 'Any', never 'Write': find_parameter filters with
% Access='Read', which drops write-only parameters, so a 'Write' trigger is
% simply never found and the session dies with epsych:RunExpt:MissingTrigger.
%
% isTrigger=true also sets UpdateEveryTrial=false, which is what keeps a
% trigger out of the per-trial parameter dispatch. It is stated in the spec so
% the intent survives a change to that setter.

specs(end + 1) = local_spec_(sprintf('x_ResetTrig_%d', B), false, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, 'isTrigger', true, ...
           'Description', "Pulsed by epsych.Runtime.dispatchNextTrial ahead of the per-trial writes. Aborts any matrix left running, drains the epilogue burst the firmware still emits after an abort, and clears the accumulating trial record."));

specs(end + 1) = local_spec_(sprintf('x_NewTrial_%d', B), false, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, 'isTrigger', true, ...
           'Description', "Pulsed after the per-trial writes. Rebuilds and uploads the state matrix if it changed, then sends 'R' to start the trial."));

specs(end + 1) = local_spec_(sprintf('x_TrialComplete_%d', B), false, ...
    struct('Type', 'Boolean', 'Access', 'Read', 'Visible', false, 'isTrigger', false, ...
           'Description', "Never pulsed. ep_TimerFcn_RunTime reads its Value on every 10 ms tick; hw.Bpod raises it once the matrix-end sentinel and the 10-byte epilogue have both been consumed."));

% --- Shipped-GUI literals ------------------------------------------------
% gui.OnlinePlot resolves these two names with includeInvisible=true and
% silenceParameterNotFound=true, so omitting them silently disables
% trial-locked plotting instead of raising anything. The '~<BoxID>' suffix is
% not a typo and does not match the 'x_*_<BoxID>' trigger form: OnlinePlot
% looks them up exactly as written.

specs(end + 1) = local_spec_(sprintf('_TrigState~%d', B), false, ...
    struct('Type', 'Boolean', 'Access', 'Read', 'Visible', false, ...
           'Description', "Trial-onset flag polled by gui.OnlinePlot; true while a state matrix is running."));

specs(end + 1) = local_spec_(sprintf('_TrialNum~%d', B), 0, ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', false, ...
           'Description', "Trial counter polled by gui.OnlinePlot."));

% --- Trial configuration -------------------------------------------------
% Visible and Access='Any': these are the only two parameters that become
% columns of the trial table, and they echo back into DATA so each saved trial
% records the configuration it ran under.

specs(end + 1) = local_spec_('TrialDuration', 1, ...
    struct('Type', 'Float', 'Access', 'Any', 'Visible', true, ...
           'Min', 0, 'Max', 3600, 'Unit', 's', ...
           'Description', "Nominal trial duration. Passed to the state-matrix builder; in immediate I/O mode it is the host-side trial timeout."));

specs(end + 1) = local_spec_('TrialType', 1, ...
    struct('Type', 'Integer', 'Access', 'Any', 'Visible', true, 'Min', 0, ...
           'Description', "Integer condition label for the upcoming trial. psychophysics.Detection groups by this, separately from RespCode."));

% --- Trial results -------------------------------------------------------
% Visible and Access='Read': the DATA sweep collects these, the trial table
% cannot. FROZEN field set - see the header. No Min is set on any of them so a
% NaN reported for an unvisited state survives clamp_value_ unchanged.

specs(end + 1) = local_spec_('RespCode', double(epsych.BitMask.Undefined), ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', true, ...
           'Description', "Trial outcome as an epsych.BitMask mask, e.g. epsych.BitMask.Bits2Mask(uint32([epsych.BitMask.Hit epsych.BitMask.Reward])); decode with epsych.BitMask.decode. psychophysics.Detection, BestPEST and MLP all key off this field, so dropping it silently produces no online analysis at all."));

specs(end + 1) = local_spec_('RespLatency', 0, ...
    struct('Type', 'Float', 'Access', 'Read', 'Visible', true, 'Unit', 's', ...
           'Description', "Seconds from matrix start to the first response event. NaN when the trial produced no response."));

specs(end + 1) = local_spec_('nStatesVisited', 0, ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', true, ...
           'Description', "Number of state entries recorded for the completed trial."));

specs(end + 1) = local_spec_('LastStateCode', 0, ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', true, ...
           'Description', "Manifest index of the final state. Indices in the event stream refer to post-compile manifest order (add order after sendStateMatrix permutes), not declaration order."));

specs(end + 1) = local_spec_('LastStateName', '', ...
    struct('Type', 'String', 'Access', 'Read', 'Visible', true, ...
           'Description', "Name of the final state, resolved through hw.Bpod.StateNames. Empty when the trial recorded no state."));

specs(end + 1) = local_spec_('TrialStartTimestamp', 0, ...
    struct('Type', 'Float', 'Access', 'Read', 'Visible', true, 'Unit', 's', ...
           'Description', "Device trial-start time from the epilogue header (uint32 milliseconds), converted to seconds."));

specs(end + 1) = local_spec_('TrialDuration_Actual', 0, ...
    struct('Type', 'Float', 'Access', 'Read', 'Visible', true, 'Unit', 's', ...
           'Description', "Measured duration of the completed trial, as distinct from the requested TrialDuration."));

specs(end + 1) = local_spec_('Aborted', false, ...
    struct('Type', 'Boolean', 'Access', 'Read', 'Visible', true, ...
           'Description', "True when the trial ended by abortMatrix, by the epilogue watchdog, or by the MaxTrialSeconds ceiling rather than by reaching an exit state."));

specs(end + 1) = local_spec_('LastSoftCode', 0, ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', true, ...
           'Description', "Most recent soft code delivered during the trial; 0 when none was sent. Note SoftCode1 is wire code 0."));

specs(end + 1) = local_spec_('StateCodes', [], ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', true, 'isArray', true, ...
           'Description', "Manifest indices of every state entered, in order of entry."));

specs(end + 1) = local_spec_('StateTimestamps', [], ...
    struct('Type', 'Float', 'Access', 'Read', 'Visible', true, 'isArray', true, 'Unit', 's', ...
           'Description', "Entry time of each element of StateCodes, in seconds from matrix start."));

specs(end + 1) = local_spec_('EventCodes', [], ...
    struct('Type', 'Integer', 'Access', 'Read', 'Visible', true, 'isArray', true, ...
           'Description', "Every event byte the device streamed during the trial, in order. Index into hw.Bpod.EVENT_NAMES to name them."));

specs(end + 1) = local_spec_('EventTimestamps', [], ...
    struct('Type', 'Float', 'Access', 'Read', 'Visible', true, 'isArray', true, 'Unit', 's', ...
           'Description', "Seconds from matrix start for each element of EventCodes. The firmware stops recording past MAX_TIMESTAMPS while the state machine keeps running, so this can legitimately be shorter than EventCodes."));

end


function s = local_spec_(name, value, options)
% s = local_spec_(name, value, options)
% Build one parameter spec, or the empty spec array when called with no
% arguments.
%
% The field order is fixed here so that specs built in different sections
% always concatenate into one struct array.
fields = {'Name', 'Value', 'Options'};

if nargin == 0
    args = [fields; repmat({{}}, 1, numel(fields))];
    s = struct(args{:});
    return
end

s = struct('Name', char(name), 'Value', value, 'Options', options);

end
