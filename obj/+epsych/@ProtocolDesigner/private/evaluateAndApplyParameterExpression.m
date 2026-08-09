function appliedText = evaluateAndApplyParameterExpression(obj, parameter, expressionText)
% appliedText = evaluateAndApplyParameterExpression(obj, parameter, expressionText)
% Evaluate a parameter expression and write the normalized result back to the parameter.
%
% Parameters:
%	parameter	- Target parameter to update.
%	expressionText	- Expression text to evaluate in the current parameter context.
%
% Returns:
%	appliedText	- Short description of what the expression produced, for the
%			  status line.
    if ~obj.parameterSupportsExpression(parameter)
        if parameter.isTrigger
            error('Parameter %s is a trigger, and triggers fire rather than carrying a value that an expression could set.', parameter.Name);
        end
        error('Parameter %s does not support expressions for type %s.', parameter.Name, parameter.Type);
    end

    result = obj.evaluateParameterExpression(parameter, expressionText);
    result = obj.normalizeExpressionResult(parameter, result);

    if hw.Parameter.expressionSelectsIndex(parameter.Type)
        % Values holds the selectable items, not computed levels: the expression
        % picks one of them on every dispatch, so the item list stays as the user
        % entered it. normalizeExpressionResult already verified the index.
        [item, index] = hw.Parameter.selectValueByIndex(result, parameter.Values, parameter.Name);
        appliedText = sprintf('item %d of %d (%s)', index, numel(parameter.Values), ...
            obj.formatExpressionItem(item));
        return
    end

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

    appliedText = obj.getParameterValueDisplay(parameter);
end
