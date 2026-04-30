function context = buildExpressionContext(obj, targetParameter)
% context = buildExpressionContext(obj, targetParameter)
% Build the parameter-value context used to evaluate expressions for one parameter.
%
% Parameters:
%	targetParameter	- Parameter whose module scope defines the available references.
%
% Returns:
%	context	- Struct mapping expression aliases to numeric values.
    parameters = obj.getAllParameters();
    context = struct();
    targetModule = targetParameter.Module;

    for idx = 1:numel(parameters)
        parameter = parameters(idx);
        if isequal(parameter, targetParameter)
            continue
        end
        if ~obj.parameterCanParticipateInExpression(parameter)
            continue
        end

        if isequal(parameter.Module, targetModule)
            context.(parameter.Name) = localValuesToNumeric_(parameter.Values);
        end

        context.(obj.getQualifiedExpressionAlias(parameter)) = localValuesToNumeric_(parameter.Values);
    end
end

function val = localValuesToNumeric_(values)
    % Convert a 1×N cell of trial levels to a numeric vector for expression context.
    if isempty(values)
        val = 0;
        return
    end
    numeric_vals = cellfun(@(v) double(v), values(cellfun(@(v) isnumeric(v) || islogical(v), values)), ...
        'UniformOutput', false);
    if isempty(numeric_vals)
        val = 0;
    else
        val = [numeric_vals{:}];
    end
end

