function [tf, msg] = readHardwareParameters(obj, module, options)
% [tf, msg] = readHardwareParameters(obj, module)
% [tf, msg] = readHardwareParameters(obj, module, Mode='replace')
% Discover the module's parameters from the Synapse server.
%
% Uses the live connection when available; otherwise a temporary SynapseAPI
% client is created for read-only info queries and released afterwards.
% Deliberately does NOT call connect(): that forces Synapse into Standby,
% which may not happen as a side effect of a parameter read. What it does
% record besides the parameters is the gizmo's category and sample rate,
% so a protocol authored in ProtocolDesigner knows before any run whether
% its module is a legacy processor and what rate its stimuli play at.
%
% The module is placed by its Label or its Name (resolveGizmo_). One Synapse
% recognizes neither of is reported with the names it does, since both are
% typed by hand and a legacy processor's is not obvious ('RZ6(1)', not
% 'RZ6').
%
% See also: hw.Interface.readHardwareParameters,
%   hw.TDT_Synapse.populateModuleParametersFromGizmo

arguments
    obj
    module (1,1) hw.Module
    options.Mode (1,:) char {mustBeMember(options.Mode,{'merge','replace'})} = 'merge'
end

tf = false;

if ~any(obj.Module == module)
    msg = sprintf('Module "%s" does not belong to this %s interface.', ...
        module.Name, char(obj.Type));
    return
end

try
    if obj.IsConnected && ~isempty(obj.HW)
        api = obj.HW;
    else
        api = obj.createApi_();
        cleanup = onCleanup(@() obj.releaseApi_(api));
    end

    [gizmo, known] = obj.resolveGizmo_(api, module);
    if isempty(gizmo) && ~isempty(known)
        msg = sprintf(['%s: Synapse at %s has no object named "%s" or "%s". It has: %s. Set the ' ...
            'module Label to the name exactly as Synapse shows it (a processor in legacy mode ' ...
            'is its own object, listed with its instance number).'], ...
            module.Name, obj.Server, module.Label, module.Name, strjoin(known, ', '));
        return
    end

    if strcmp(options.Mode, 'replace')
        module.Parameters = hw.Parameter.empty(1, 0);
    end

    [nAdded, nSkipped] = obj.populateModuleParametersFromGizmo(module, api);
    obj.ensureUniqueParameterNames();

    rates = struct();
    try
        rates = api.getSamplingRates();
    catch ME
        vprintf(3,'Sampling rates unavailable while reading parameters: %s', ME.message)
    end
    obj.bindGizmoInfo_(api, module, rates);

    tf = true;
    if nAdded == 0 && nSkipped == 0
        msg = sprintf(['%s: no parameters found. "%s" exposes no API parameter -- for a gizmo, ' ...
            'enable API access in its options; for a processor in legacy mode, check the ' ...
            'circuit has parameter tags.'], module.Name, obj.gizmoName_(module));
    else
        msg = sprintf('%s: added %d parameter(s), %d already present%s.', ...
            module.Name, nAdded, nSkipped, local_legacyNote(obj, module));
    end
catch ME
    vprintf(2, 'readHardwareParameters failed for module "%s": %s', module.Name, ME.message)
    msg = sprintf('Cannot read parameters from Synapse at %s: %s', obj.Server, ME.message);
end

end


function s = local_legacyNote(obj, module)
if obj.isLegacyModule(module)
    s = sprintf(' (legacy-mode processor @ %g Hz)', module.Fs);
else
    s = '';
end
end
