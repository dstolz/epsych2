function parameterName = validateParameterName(~, parameterName)
    if isstring(parameterName)
        parameterName = char(parameterName);
    end

    parameterName = strtrim(parameterName);
    if isempty(parameterName)
        error('Parameter name cannot be empty.');
    end
end