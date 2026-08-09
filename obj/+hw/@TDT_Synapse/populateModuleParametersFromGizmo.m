function [nAdded, nSkipped] = populateModuleParametersFromGizmo(obj, module, api)
% [nAdded, nSkipped] = populateModuleParametersFromGizmo(obj, module, api)
% Append hw.Parameter objects to a module from a Synapse gizmo's parameter
% metadata.
%
% Single source of truth for turning SynapseAPI parameter info into
% hw.Parameter objects; used by setup_interface and readHardwareParameters.
%
% Parameters:
%   module - hw.Module whose Label names the Synapse gizmo/device.
%   api    - SynapseAPI client to query (a live obj.HW or a temporary one).
%
% Parameters whose hardware name already exists on the module are skipped,
% so the operation is idempotent and preserves user edits. Parameters for
% which Synapse returns no info are skipped rather than erroring.
%
% Returns:
%   nAdded   - Number of parameters appended to module.Parameters.
%   nSkipped - Number of parameters skipped because they already exist.
%
% See also: hw.TDT_Synapse.readHardwareParameters, SynapseAPI

nAdded = 0;
nSkipped = 0;

names = api.getParameterNames(module.Label);
if isempty(names)
    return
end

% remove reserved TDT parameters
reserved = characterListPattern('%/|\#');
names = names(~startsWith(names, reserved));

existingNames = arrayfun(@hw.Interface.getHardwareParameterName, ...
    module.Parameters, 'UniformOutput', false);

for k = 1:numel(names)
    name = names{k};
    if any(strcmp(existingNames, name))
        nSkipped = nSkipped + 1;
        continue
    end

    t = api.getParameterInfo(module.Label, name);
    if isempty(fieldnames(t))
        % Synapse returned no info for this parameter (getParameterInfo
        % yields an empty struct); skip rather than build a bogus entry.
        continue
    end

    P = hw.Parameter(obj);

    P.Name = t.Name;
    obj.setHardwareParameterName(P, t.Name);
    P.Unit = t.Unit;
    P.Min = t.Min;
    P.Max = t.Max;
    P.Access = t.Access;
    P.Type = t.Type;
    P.isArray = isequal(t.Array, 'Yes');

    P.Module = module;

    P.isTrigger = P.Name(1) == '!'; % our convention for indicating a trigger
    P.Visible = ~any(P.Name(1) == '_~'); % core macro / hidden parameter conventions

    module.Parameters(end+1) = P;
    nAdded = nAdded + 1;
end

end
