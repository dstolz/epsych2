function validateExpressionReferences(obj, targetParameter, expressionText)
    identifiers = regexp(expressionText, '(?<!\.)\<[A-Za-z]\w*\>', 'match');
    if isempty(identifiers)
        return
    end

    parameters = obj.getAllParameters();
    for idx = 1:numel(parameters)
        parameter = parameters(idx);
        if isequal(parameter, targetParameter)
            continue
        end

        aliases = obj.getExpressionAliases(parameter, parameters);
        if isempty(aliases)
            continue
        end

        usedAlias = aliases(find(ismember(aliases, identifiers), 1, 'first'));
        if isempty(usedAlias)
            continue
        end

        if ~obj.parameterCanParticipateInExpression(parameter)
            error('Expression references %s, but parameter %s cannot be used in expressions for type %s.', ...
                usedAlias{1}, parameter.Name, parameter.Type);
        end
    end
end

