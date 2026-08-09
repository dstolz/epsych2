function expressionText = getParameterExpression(~, parameter)
    expressionText = char(strtrim(parameter.Expression));
    if ~isempty(expressionText)
        return
    end

    if ~isstruct(parameter.UserData)
        return
    end

    if isfield(parameter.UserData, 'Expression') && ~isempty(parameter.UserData.Expression)
        expressionText = char(strtrim(string(parameter.UserData.Expression)));
        if ~isempty(expressionText)
            parameter.Expression = string(expressionText);
            parameter.UserData = rmfield(parameter.UserData, 'Expression');
        end
    end
end

