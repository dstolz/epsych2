function text = getUniqueModuleText(~, iface, requestedText, propertyName)
    text = strtrim(char(string(requestedText)));
    if isempty(text)
        text = 'Module';
    end

    existingValues = cell(1, length(iface.Module));
    for idx = 1:length(iface.Module)
        existingValues{idx} = iface.Module(idx).(propertyName);
    end

    if ~any(strcmp(existingValues, text))
        return
    end

    baseText = text;
    suffix = 2;
    while any(strcmp(existingValues, text))
        text = sprintf('%s_%d', baseText, suffix);
        suffix = suffix + 1;
    end
end