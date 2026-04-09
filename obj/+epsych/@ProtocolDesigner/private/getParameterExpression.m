function expressionText = getParameterExpression(~, parameter)
    expressionText = '';
    if ~isstruct(parameter.UserData)
        return
    end
    if isfield(parameter.UserData, 'Expression') && ~isempty(parameter.UserData.Expression)
        expressionText = char(string(parameter.UserData.Expression));
    end
end

