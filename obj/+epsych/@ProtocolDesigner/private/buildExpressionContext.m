function context = buildExpressionContext(obj, targetParameter)
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
            context.(parameter.Name) = double(parameter.Value);
        end

        context.(obj.getQualifiedExpressionAlias(parameter)) = double(parameter.Value);
    end
end

