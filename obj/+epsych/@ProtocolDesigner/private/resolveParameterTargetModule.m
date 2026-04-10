function module = resolveParameterTargetModule(obj, parameter, requestedModule)
    module = parameter.Module;
    iface = module.parent;
    requestedText = strtrim(char(string(requestedModule)));
    if isempty(requestedText)
        error('Module cannot be empty.');
    end

    moduleIndex = obj.parseIndexedLabel(requestedText);
    if moduleIndex >= 1 && moduleIndex <= length(iface.Module)
        module = iface.Module(moduleIndex);
        return
    end

    for idx = 1:length(iface.Module)
        candidate = iface.Module(idx);
        if strcmpi(requestedText, candidate.Name) || strcmpi(requestedText, candidate.Label) ...
                || strcmpi(requestedText, obj.moduleDisplayLabel(candidate, idx))
            module = candidate;
            return
        end
    end

    moduleChoices = arrayfun(@(idx) obj.moduleDisplayLabel(iface.Module(idx), idx), 1:length(iface.Module), 'UniformOutput', false);
    error('Unknown module "%s". Use one of: %s', requestedText, strjoin(moduleChoices, ', '));
end