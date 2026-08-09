function tf = hasParameterExpression(obj, parameter)
    expressionText = obj.getParameterExpression(parameter);
    tf = strlength(string(expressionText)) > 0;
end

