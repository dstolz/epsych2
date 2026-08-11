function convertedNames = normalizeConstantExpressions(obj)
% convertedNames = normalizeConstantExpressions(obj)
% Convert stored literal-constant Expressions ("0", "500") into fixed
% design-time Values across the bound protocol.
%
% Protocols written before the designer stored constants as values carry an
% Expression for every numeric parameter, because the Expression column was
% the only way to enter a value. A constant Expression on a dispatched
% (UpdateEveryTrial) parameter is poison at runtime: hw.Parameter.set.Value
% re-derives the constant on every per-trial assignment, overriding whatever
% the runtime wrote - a staircase updating Depth through the trial table
% stays pinned at the constant forever. Converting on load heals such
% protocols as they are reopened and saved.
%
% Only scalar literals on value-computing types (Float, Integer, Boolean) are
% converted. Index-selecting types (String, StimType) keep constant
% expressions: there the constant deliberately pins which item is used while
% Values holds the full item list. Text that references parameters or calls
% functions is left untouched, as is anything that fails to evaluate.
%
% Returns:
%	convertedNames	- Cell array of converted parameter names (qualified as
%			  Module.Parameter), empty when nothing changed.

    convertedNames = {};
    parameters = obj.getAllParameters();

    for k = 1:numel(parameters)
        parameter = parameters(k);

        expressionText = obj.getParameterExpression(parameter);
        if isempty(expressionText) || ~obj.parameterSupportsExpression(parameter)
            continue
        end
        if hw.Parameter.expressionSelectsIndex(parameter.Type)
            continue
        end
        if ~obj.isLiteralConstantExpression(expressionText)
            continue
        end

        try
            result = obj.evaluateParameterExpression(parameter, expressionText);
            result = obj.normalizeExpressionResult(parameter, result);
        catch
            % Leave anything unevaluable exactly as loaded.
            continue
        end

        parameter.Values = hw.Parameter.normalizeValues(result);
        parameter.isArray = numel(result) > 1;
        obj.clearParameterExpression(parameter);
        convertedNames{end + 1} = sprintf('%s.%s', parameter.Module.Name, parameter.Name); %#ok<AGROW>
    end
end
