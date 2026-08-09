function setParameterExpression(obj, parameter, expressionText)
    if ~obj.parameterSupportsExpression(parameter)
        if parameter.isTrigger
            error('Trigger parameters cannot use expressions because a trigger fires rather than carrying a value.');
        end
        error(['Expressions are not available for %s parameters. Use Float, Integer, or Boolean to calculate ' ...
            'a value, or String or StimType to select one of the parameter''s items by index.'], parameter.Type);
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
