function setParameterExpression(obj, parameter, expressionText)
    if ~obj.parameterSupportsExpression(parameter)
        error('Expressions are only allowed for Float, Integer, or Boolean parameter types.');
    end

    expressionText = strtrim(char(string(expressionText)));
    if isempty(expressionText)
        obj.clearParameterExpression(parameter);
        return
    end

    parameter.Expression = string(expressionText);

    if isstruct(parameter.UserData) && isfield(parameter.UserData, 'Expression')
        parameter.UserData = rmfield(parameter.UserData, 'Expression');
    end
end

