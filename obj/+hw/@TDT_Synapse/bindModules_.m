function bindModules_(obj, api)
% bindModules_(obj, api)
% Check every protocol-authored module against the server and fill in what
% only the server knows.
%
% A module's Synapse name -- its Label, or its Name (see resolveGizmo_) --
% is what every read, write and trigger is addressed to, typed by whoever
% built the protocol; a name Synapse does not recognize is the likeliest
% mistake and the one that would otherwise surface as a failed write on
% trial one. So the check is at connect, and the error names what Synapse
% does have. Sample rate, category and parent processor are refreshed on
% every connect, since a protocol may have been authored offline or against
% another rig.
%
% Parameters already on a module are kept untouched -- they carry the
% protocol's Values and trial options -- and only a module with none is
% populated. For a populated module, two things are reported once here
% rather than once per trial by the write that fails: tags the circuit no
% longer has, and tags that are ARRAYS on the device but scalars in the
% protocol. The second is the legacy-mode trap: while Synapse is Idle it
% describes every tag of a legacy circuit as a scalar Float, so a protocol
% built from ProtocolDesigner's Read HW Params has its stimulus and
% coefficient buffers typed as scalars until someone sets them by hand, and
% connect -- Standby, where Synapse reports sizes -- is the first moment
% anything can notice.
%
% See also: hw.TDT_Synapse.discoverModules_, hw.TDT_Synapse.setup_interface

rates = struct();
try
    rates = api.getSamplingRates();
catch ME
    vprintf(2,'Could not read sampling rates from Synapse: %s', ME.message)
end

for module = obj.Module
    [gizmo, known] = obj.resolveGizmo_(api, module);
    if isempty(gizmo)
        error('hw:TDT_Synapse:UnknownGizmo', ...
            ['Module "%s" (label "%s"): neither its Name nor its Label is an object in the ' ...
            'Synapse experiment at %s. Synapse has: %s. Put the name exactly as Synapse ' ...
            'shows it in the module''s Label; a processor in legacy mode is its own object, ' ...
            'listed with its instance number (''RZ6(1)'', not ''RZ6'').'], ...
            module.Name, module.Label, obj.Server, local_list(known));
    end

    obj.bindGizmoInfo_(api, module, rates);

    if isempty(module.Parameters)
        nAdded = obj.populateModuleParametersFromGizmo(module, api);
        vprintf(2,'Synapse module "%s": discovered %d parameter(s)', gizmo, nAdded)
        continue
    end

    local_reportDrift(obj, module, api, gizmo);
end

end


function local_reportDrift(obj, module, api, gizmo)
% Neither finding is fatal -- a missing tag may be read-only or never
% dispatched, and a buffer written as a scalar fails on its own write -- but
% both are news the operator should get before the first trial, in one line
% each, not as a failure per trial.
available = api.getParameterNames(gizmo);
if isempty(available)
    available = {};
elseif ischar(available) || isstring(available)
    available = cellstr(available);
end

hardwareNames = arrayfun(@hw.Interface.getHardwareParameterName, ...
    module.Parameters, 'UniformOutput', false);
present = ismember(hardwareNames, available);

missing = hardwareNames(~present);
if ~isempty(missing)
    vprintf(0,1,['Module "%s": %d parameter(s) in the protocol have no tag in what Synapse ' ...
        'loaded (%s). Writes to them will fail.'], ...
        gizmo, numel(missing), strjoin(missing, ', '))
end

arrayTypes = [obj.ARRAY_TYPES, {'StimType'}];
scalarsThatAreArrays = {};
for k = find(present)
    p = module.Parameters(k);
    if p.isArray || ismember(p.Type, arrayTypes)
        continue
    end
    try
        info = api.getParameterInfo(gizmo, hardwareNames{k});
    catch
        continue
    end
    spec = hw.TDT_Synapse.parameterSpecFromInfo(hardwareNames{k}, info);
    if spec.isArray
        scalarsThatAreArrays{end+1} = sprintf('%s (%g elements)', p.Name, spec.Size);
    end
end

if ~isempty(scalarsThatAreArrays)
    vprintf(0,1,['Module "%s": %d parameter(s) are arrays on the device but scalars in the ' ...
        'protocol (%s). Set their Type to Buffer, Coefficient Buffer or StimType in ' ...
        'ProtocolDesigner: a design-time read of a legacy circuit reports every tag as a ' ...
        'scalar Float.'], ...
        gizmo, numel(scalarsThatAreArrays), strjoin(scalarsThatAreArrays, ', '))
end
end


function s = local_list(names)
if isempty(names)
    s = '(nothing)';
else
    s = strjoin(names, ', ');
end
end
