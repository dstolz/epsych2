function setParameterExpression(obj, parameter, expressionText)
    if ~obj.parameterSupportsExpression(parameter)
        error('Expressions are only allowed for numeric scalar parameter types.');
    end

    expressionText = strtrim(char(string(expressionText)));
    if isempty(expressionText)
        obj.clearParameterExpression(parameter);
        return
    end

    if isempty(parameter.UserData) || ~isstruct(parameter.UserData)
        parameter.UserData = struct();
    end
    parameter.UserData.Expression = expressionText;
end

