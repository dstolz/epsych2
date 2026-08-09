function allowMultiple = resolveFileSelectionMode(obj, parameter)
    configuredMode = obj.getParameterFileConfig(parameter).allowMultiple;
    if isempty(configuredMode)
        allowMultiple = parameter.isArray;
    else
        allowMultiple = configuredMode;
    end
end

