function [tf, msg] = readHardwareParameters(obj, module, options)
% [tf, msg] = readHardwareParameters(obj, module)
% [tf, msg] = readHardwareParameters(obj, module, Mode='replace')
% Discover the module's parameters from the Synapse server.
%
% Uses the live connection when available; otherwise a temporary SynapseAPI
% client is created for read-only info queries and released afterwards.
% Deliberately does NOT call connect(): setup_interface rebuilds obj.Module
% (destroying designer-authored modules) and forces Synapse into Standby,
% neither of which may happen as a side effect of a parameter read.
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
        if isempty(which('SynapseAPI'))
            msg = 'SynapseAPI not found on Matlab''s path. Run epsych_startup.';
            return
        end
        api = SynapseAPI(obj.Server);
        cleanup = onCleanup(@() delete(api));
    end

    if strcmp(options.Mode, 'replace')
        module.Parameters = hw.Parameter.empty(1, 0);
    end

    [nAdded, nSkipped] = obj.populateModuleParametersFromGizmo(module, api);
    obj.ensureUniqueParameterNames();

    tf = true;
    if nAdded == 0 && nSkipped == 0
        msg = sprintf('%s: no parameters found — check that the module Label "%s" matches a Synapse gizmo/device name.', ...
            module.Name, module.Label);
    else
        msg = sprintf('%s: added %d parameter(s), %d already present.', ...
            module.Name, nAdded, nSkipped);
    end
catch ME
    vprintf(2, 'readHardwareParameters failed for module "%s": %s', module.Name, ME.message)
    msg = sprintf('Cannot read parameters from Synapse at %s: %s', obj.Server, ME.message);
end

end
