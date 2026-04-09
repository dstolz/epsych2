function evaluateAndApplyParameterExpression(obj, parameter, expressionText)
    if ~obj.parameterSupportsExpression(parameter)
        error('Parameter %s does not support expressions for type %s.', parameter.Name, parameter.Type);
    end

    result = obj.evaluateParameterExpression(parameter, expressionText);
    result = obj.normalizeExpressionResult(parameter, result);

    parameter.Value = result;
end

