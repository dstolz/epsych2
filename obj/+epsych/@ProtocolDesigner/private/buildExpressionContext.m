function context = buildExpressionContext(obj, targetParameter)
    parameters = obj.getAllParameters();
    context = struct();

    for idx = 1:numel(parameters)
        parameter = parameters(idx);
        if isequal(parameter, targetParameter)
            continue
        end
        if ~obj.parameterCanParticipateInExpression(parameter)
            continue
        end

        aliases = obj.getExpressionAliases(parameter, parameters);
        for aliasIdx = 1:numel(aliases)
            context.(aliases{aliasIdx}) = double(parameter.Value);
        end
    end
end

