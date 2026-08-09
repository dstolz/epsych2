function numericValue = getSingleModuleOptionNumeric(~, moduleOptions, fieldName, fallbackValue)
    if ~isfield(moduleOptions, fieldName)
        numericValue = fallbackValue;
        return
    end

    rawValue = moduleOptions.(fieldName);
    if isempty(rawValue)
        numericValue = fallbackValue;
        return
    end

    if numel(rawValue) ~= 1
        error('Module option "%s" must contain exactly one value.', fieldName);
    end

    numericValue = double(rawValue);
    if isnan(numericValue)
        numericValue = fallbackValue;
    end
end