function textValue = getSingleModuleOptionText(~, moduleOptions, fieldName, fallbackValue)
    if ~isfield(moduleOptions, fieldName)
        textValue = fallbackValue;
        return
    end

    rawValue = moduleOptions.(fieldName);
    if iscell(rawValue)
        if isempty(rawValue)
            textValue = fallbackValue;
            return
        end
        if numel(rawValue) ~= 1
            error('Module option "%s" must contain exactly one value.', fieldName);
        end
        textValue = char(string(rawValue{1}));
    else
        textValue = char(string(rawValue));
    end

    textValue = strtrim(textValue);
    if isempty(textValue)
        textValue = fallbackValue;
    end
end