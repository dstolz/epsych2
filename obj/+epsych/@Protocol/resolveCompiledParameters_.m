function parameters = resolveCompiledParameters_(obj)
% parameters = resolveCompiledParameters_(obj)
%
% Rebuild obj.COMPILED.parameters by resolving serialized COMPILED.writeparams
% names against the writable parameters currently present on obj.Interfaces.
%
% Returns:
%   parameters - Ordered hw.Parameter array matching COMPILED.writeparams

parameters = hw.Parameter.empty(1, 0);
if ~isfield(obj.COMPILED, 'writeparams') || isempty(obj.COMPILED.writeparams)
    return
end

writeparams = obj.COMPILED.writeparams;

allParams = hw.Parameter.empty(1, 0);
allParamAliases = cell(1, 0);

for ifaceIdx = 1:length(obj.Interfaces)
    iface = obj.Interfaces(ifaceIdx);
    ifaceType = char(iface.Type);

    for moduleIdx = 1:length(iface.Module)
        module = iface.Module(moduleIdx);

        for paramIdx = 1:length(module.Parameters)
            parameter = module.Parameters(paramIdx);
            if ~parameter.Visible || strcmp(parameter.Access, 'Read')
                continue
            end

            allParams(end + 1) = parameter; %#ok<AGROW>
            allParamAliases{end + 1} = localBuildParameterAliases_(obj, parameter, ifaceType, module); %#ok<AGROW>
        end
    end
end

if isempty(allParams)
    return
end

used = false(1, numel(allParams));
unresolved = cell(1, 0);

for idx = 1:numel(writeparams)
    targetName = char(string(writeparams{idx}));
    if isempty(targetName)
        unresolved{end + 1} = '<empty>'; %#ok<AGROW>
        continue
    end

    matchIdx = [];
    for candIdx = 1:numel(allParams)
        if used(candIdx)
            continue
        end

        aliases = allParamAliases{candIdx};
        if any(strcmp(targetName, aliases))
            matchIdx = candIdx;
            break
        end
    end

    if isempty(matchIdx)
        unresolved{end + 1} = targetName; %#ok<AGROW>
        continue
    end

    used(matchIdx) = true;
    parameters(end + 1) = allParams(matchIdx); %#ok<AGROW>
end

if ~isempty(unresolved)
    vprintf(0, 1, 'Protocol load warning: Could not resolve %d compiled parameter(s): %s', ...
        numel(unresolved), strjoin(unresolved, ', '));
end
end

function aliases = localBuildParameterAliases_(obj, parameter, ifaceType, module)
% localBuildParameterAliases_ Build accepted serialized names for a parameter.

compiledName = obj.getCompiledParameterName_(parameter, ifaceType, module);
nameRaw = char(string(parameter.Name));
nameValid = char(string(parameter.validName));
qualifiedName = sprintf('%s.%s', module.Name, parameter.Name);

aliases = unique({compiledName, nameRaw, nameValid, qualifiedName}, 'stable');
end
