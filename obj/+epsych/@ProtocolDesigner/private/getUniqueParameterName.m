function uniqueName = getUniqueParameterName(obj, module, baseName)
    if isstring(baseName)
        baseName = char(baseName);
    end

    baseName = strtrim(baseName);
    if isempty(baseName)
        baseName = 'param';
    end
    baseName = obj.validateParameterName(baseName);

    existingNames = {module.Parameters.Name};
    uniqueName = baseName;
    suffix = 1;
    while any(strcmp(uniqueName, existingNames))
        uniqueName = sprintf('%s_%d', baseName, suffix);
        suffix = suffix + 1;
    end
end
