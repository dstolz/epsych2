function parameterName = validateParameterName(~, parameterName)
    if isstring(parameterName)
        parameterName = char(parameterName);
    end

    parameterName = strtrim(parameterName);
    if isempty(parameterName)
        error('Parameter name cannot be empty.');
    end

    validName = char(matlab.lang.makeValidName(parameterName));
    if ~strcmp(parameterName, validName)
        error('Parameter names must be valid MATLAB identifiers. "%s" is invalid. Use "%s" instead.', ...
            parameterName, validName);
    end
end