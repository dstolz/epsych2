function [nAdded, nSkipped] = populateModuleParametersFromGizmo(obj, module, api)
% [nAdded, nSkipped] = populateModuleParametersFromGizmo(obj, module, api)
% Append hw.Parameter objects to a module from a Synapse gizmo's parameter
% metadata.
%
% Single source of truth for turning SynapseAPI parameter info into
% hw.Parameter objects; used by connect (through discoverModules_ and
% bindModules_) and by readHardwareParameters. The vocabulary Synapse
% speaks is not hw.Parameter's -- 'Int' for Integer, 'Logic' for Boolean,
% an array size that is the word 'Yes' at design time and a number at
% runtime -- so every field goes through hw.TDT_Synapse.parameterSpecFromInfo,
% and a tag Synapse lists but will not describe (the old integration met
% these on triggers inside circuit macros) is still created, with the
% conservative metadata that function supplies, rather than dropped: a
% parameter that is not there cannot be triggered. What Synapse actually
% said is kept on the parameter as UserData.SynapseInfo.
%
% Parameters:
%   module - hw.Module whose Label names the Synapse gizmo (or legacy
%            processor).
%   api    - SynapseAPI client to query (a live obj.HW or a temporary one).
%
% Parameters whose hardware name already exists on the module are skipped,
% so the operation is idempotent and preserves user edits.
%
% Returns:
%   nAdded   - Number of parameters appended to module.Parameters.
%   nSkipped - Number of parameters skipped because they already exist.
%
% See also: hw.TDT_Synapse.parameterSpecFromInfo, hw.TDT_Synapse.filterParameterNames,
%   hw.TDT_Synapse.readHardwareParameters, SynapseAPI

nAdded = 0;
nSkipped = 0;

gizmo = obj.gizmoName_(module);
names = api.getParameterNames(gizmo);
if isempty(names)
    return
end
if ischar(names) || isstring(names)
    names = cellstr(names);
end

[names, dropped] = hw.TDT_Synapse.filterParameterNames(names);
for d = dropped
    vprintf(3,'%s: tag "%s" not exposed (%s)', gizmo, d.Name, d.Reason)
end

existingNames = arrayfun(@hw.Interface.getHardwareParameterName, ...
    module.Parameters, 'UniformOutput', false);

for k = 1:numel(names)
    name = names{k};
    if any(strcmp(existingNames, name))
        nSkipped = nSkipped + 1;
        continue
    end

    % getParameterInfo yields a struct with no fields when Synapse has
    % nothing to say, and throws when the client cannot parse the reply;
    % both mean "undescribed", which parameterSpecFromInfo handles.
    info = struct();
    try
        info = api.getParameterInfo(gizmo, name);
    catch ME
        vprintf(2,'%s: no parameter info for "%s": %s', gizmo, name, ME.message)
    end

    [spec, notes] = hw.TDT_Synapse.parameterSpecFromInfo(name, info);
    for n = 1:numel(notes)
        vprintf(2,'%s.%s: %s', gizmo, name, notes(n))
    end

    P = hw.Parameter(obj);

    P.Name = name;
    obj.setHardwareParameterName(P, name);
    P.Unit = spec.Unit;
    P.Type = spec.Type;
    P.Access = spec.Access;
    P.Min = spec.Min;
    P.Max = spec.Max;
    P.isArray = spec.isArray;
    P.isTrigger = spec.isTrigger;
    P.Visible = spec.Visible;

    if spec.Described
        P.UserData.SynapseInfo = info;
    end

    P.Module = module;

    module.Parameters(end+1) = P;
    nAdded = nAdded + 1;
end

end
