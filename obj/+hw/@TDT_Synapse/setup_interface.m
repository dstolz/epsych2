function setup_interface(obj)
% setup_interface(obj)
% Open the SynapseAPI client, bring Synapse to Standby, and bind the
% interface's modules to the gizmos the server reports.
%
% Standby is the lowest mode in which Synapse answers parameter reads and
% writes, and the one in which a legacy processor has its RPvdsEx circuit
% loaded, so it is where a connected interface waits between runs. A server
% found above Standby is taken through Idle first: Synapse reloads every
% circuit on the way back up, so the session starts from a known device
% state rather than inheriting whatever another client left running.
%
% Modules are bound, never rebuilt: an interface that already holds modules
% (a protocol loaded from disk, or authored in ProtocolDesigner) keeps them,
% and connect only checks each against the server and populates the ones
% with no parameters. Only an interface with no modules at all discovers
% them. Rebuilding here used to throw away every parameter the protocol
% had configured, on every Run.
%
% Called by hw.TDT_Synapse.connect, which releases the client if this throws.
%
% See also: hw.TDT_Synapse.connect, hw.TDT_Synapse.discoverModules_,
%   hw.TDT_Synapse.bindModules_

vprintf(2,'Establishing Synapse API at %s', obj.Server)

obj.HW = obj.createApi_();
obj.ParameterSizes_ = containers.Map('KeyType', 'char', 'ValueType', 'double');

current = obj.HW.getMode();
if current < double(hw.DeviceState.Idle)
    error('hw:TDT_Synapse:NoServer', ...
        ['Synapse at %s did not report a mode. Check that Synapse is running with its ' ...
        'server enabled (Menu > Preferences) and that the Server name is right.'], obj.Server);
end

% Each change is waited for: Synapse takes seconds over one, and will not
% take a second request while the first is in progress.
if current > double(hw.DeviceState.Idle)
    actual = obj.awaitMode_(hw.DeviceState.Idle);
    if actual ~= hw.DeviceState.Idle
        error('hw:TDT_Synapse:ModeRejected', ...
            'Synapse at %s did not return to Idle within %g s; it is in %s.', ...
            obj.Server, obj.ModeTimeout, char(actual));
    end
end

actual = obj.awaitMode_(hw.DeviceState.Standby);
if actual ~= hw.DeviceState.Standby
    error('hw:TDT_Synapse:ModeRejected', ...
        ['Synapse at %s did not enter Standby within %g s; it is in %s. Enable Standby Mode ' ...
        'in Synapse under Menu > Preferences, and confirm an experiment is loaded.'], ...
        obj.Server, obj.ModeTimeout, char(actual));
end

if isempty(obj.Module)
    obj.Module = obj.discoverModules_(obj.HW);
else
    obj.bindModules_(obj.HW);
end

obj.ensureUniqueParameterNames();

end
