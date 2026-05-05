function evaluateAndApplyParameterExpression(obj, parameter, expressionText)
% evaluateAndApplyParameterExpression(obj, parameter, expressionText)
% Evaluate a parameter expression and write the normalized result back to the parameter.
%
% Parameters:
%	parameter	- Target parameter to update.
%	expressionText	- Expression text to evaluate in the current parameter context.
    if ~obj.parameterSupportsExpression(parameter)
        if isequal(parameter.Type, 'Boolean')
            error('Parameter %s does not support expressions for type Boolean. Use literal values 0 or 1 for Boolean parameters.', parameter.Name);
        end
        error('Parameter %s does not support expressions for type %s.', parameter.Name, parameter.Type);
    end

    result = obj.evaluateParameterExpression(parameter, expressionText);
    result = obj.normalizeExpressionResult(parameter, result);

    parameter.Values = hw.Parameter.normalizeValues(result);
end

