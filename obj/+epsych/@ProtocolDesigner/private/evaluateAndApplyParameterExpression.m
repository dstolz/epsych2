function evaluateAndApplyParameterExpression(obj, parameter, expressionText)
% evaluateAndApplyParameterExpression(obj, parameter, expressionText)
% Evaluate a parameter expression and write the normalized result back to the parameter.
%
% Parameters:
%	parameter	- Target parameter to update.
%	expressionText	- Expression text to evaluate in the current parameter context.
    if ~obj.parameterSupportsExpression(parameter)
        error('Parameter %s does not support expressions for type %s.', parameter.Name, parameter.Type);
    end

    result = obj.evaluateParameterExpression(parameter, expressionText);
    result = obj.normalizeExpressionResult(parameter, result);

    parameter.Values = hw.Parameter.normalizeValues(result);
end

