function candidates = getReplacementCandidates(obj, scope)
% candidates = getReplacementCandidates(obj, scope)
% Collect the parameters a Find and Replace should consider, in table order.
%
% Parameters:
%	scope	- 'all' (every parameter), 'shown' (rows currently in the parameter
%		  table, so interface, module, and Find filters all apply), or
%		  'selected' (the selected table row only).
%
% Returns:
%	candidates	- Struct array with fields Parameter, Module, ModuleKey, Location.
%			  ModuleKey identifies the owning module for uniqueness checks.
    candidates = struct('Parameter', {}, 'Module', {}, 'ModuleKey', {}, 'Location', {});

    switch lower(char(string(scope)))
        case 'shown'
            allowed = obj.ParameterHandles;
        case 'selected'
            parameter = obj.getSelectedParameter();
            if isempty(parameter)
                allowed = {};
            else
                allowed = {parameter};
            end
        otherwise
            allowed = {};  % unused; 'all' skips the membership test
    end
    restrictToAllowed = ~strcmpi(scope, 'all');

    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        ifaceLabel = obj.interfaceLabel(iface, ifaceIdx);

        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            moduleKey = sprintf('i%dm%d', ifaceIdx, moduleIdx);
            location = sprintf('%s > %s', ifaceLabel, obj.moduleDisplayLabel(module, moduleIdx));

            for paramIdx = 1:length(module.Parameters)
                parameter = module.Parameters(paramIdx);
                if restrictToAllowed && ~any(cellfun(@(p) isequal(p, parameter), allowed))
                    continue
                end

                candidates(end + 1) = struct( ...
                    'Parameter', parameter, ...
                    'Module', module, ...
                    'ModuleKey', moduleKey, ...
                    'Location', location); %#ok<AGROW>
            end
        end
    end
end
