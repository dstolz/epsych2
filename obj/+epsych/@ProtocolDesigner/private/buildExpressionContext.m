function context = buildExpressionContext(obj, targetParameter)
% context = buildExpressionContext(obj, targetParameter)
% Build the parameter-value context used to evaluate expressions for one parameter.
%
% Parameters:
%	targetParameter	- Parameter whose module scope defines the available references.
%
% Returns:
%	context	- Struct mapping expression aliases to numeric values and property values.
    ALLOWED_PROPS = {'Min', 'Max', 'Values', 'Value'};
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

        baseAlias = obj.getQualifiedExpressionAlias(parameter);

        if isequal(parameter.Module, targetModule)
            context.(parameter.Name) = localValuesToNumeric_(parameter.Values);
            % Sibling property aliases: Param.Prop → exprSibProp_Param_Prop
            for pIdx = 1:numel(ALLOWED_PROPS)
                propName = ALLOWED_PROPS{pIdx};
                sibAlias = matlab.lang.makeValidName(sprintf('exprSibProp_%s_%s', parameter.Name, propName));
                context.(sibAlias) = localPropertyValue_(parameter, propName);
            end
        end

        context.(baseAlias) = localValuesToNumeric_(parameter.Values);
        % Cross-module property aliases: ModuleName.Param.Prop → baseAlias_Prop
        for pIdx = 1:numel(ALLOWED_PROPS)
            propName = ALLOWED_PROPS{pIdx};
            propAlias = matlab.lang.makeValidName(sprintf('%s_%s', baseAlias, propName));
            context.(propAlias) = localPropertyValue_(parameter, propName);
        end
    end
end

function val = localPropertyValue_(parameter, propName)
    % Return the value of a named property, converting Values cell to a numeric vector.
    if strcmp(propName, 'Values')
        val = localValuesToNumeric_(parameter.Values);
    else
        val = parameter.(propName);
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

