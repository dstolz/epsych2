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

    if numel(result) > 1
        % A multi-value result defines a discrete set of trial levels rather
        % than a single derived value. Those levels are now stored in Values and
        % will be expanded into the trial table by compile(). Keeping the text as
        % a live runtime Expression would cause hw.Parameter.set.Value to
        % re-expand each per-trial level back into the full set. Drop the
        % Expression so the parameter's intent is an explicit fixed level list,
        % both in the designer and in the saved protocol.
        obj.clearParameterExpression(parameter);
    end
end

