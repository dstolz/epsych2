function validateExpressionReferences(obj, targetParameter, expressionText)
    qualifiedTokens = regexp(expressionText, '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\>', 'tokens');
    for idx = 1:numel(qualifiedTokens)
        token = qualifiedTokens{idx};
        parameter = obj.resolveQualifiedExpressionReference(targetParameter, token{1}, token{2});
        if ~obj.parameterCanParticipateInExpression(parameter)
            error('Expression references %s.%s, but parameter %s cannot be used in expressions for type %s.', ...
                token{1}, token{2}, parameter.Name, parameter.Type);
        end
    end

    bareExpressionText = regexprep(expressionText, '(?<!\.)\<[A-Za-z]\w*\>\.\<[A-Za-z]\w*\>', ' ');
    identifiers = regexp(bareExpressionText, '(?<!\.)\<[A-Za-z]\w*\>', 'match');
    if isempty(identifiers)
        return
    end

    identifiers = unique(identifiers, 'stable');
    localParameters = targetParameter.Module.Parameters;
    for idx = 1:numel(identifiers)
        identifier = identifiers{idx};
        if strcmp(identifier, targetParameter.Name)
            error('Expression cannot reference %s recursively.', identifier);
        end

        localMask = arrayfun(@(p) strcmp(p.Name, identifier) && ~isequal(p, targetParameter), localParameters);
        matches = localParameters(localMask);
        if isempty(matches)
            continue
        end

        if numel(matches) > 1
            error('Expression reference %s is ambiguous within module %s.', ...
                identifier, targetParameter.Module.Name);
        end

        parameter = matches(1);
        if ~obj.parameterCanParticipateInExpression(parameter)
            error('Expression references %s, but parameter %s cannot be used in expressions for type %s.', ...
                identifier, parameter.Name, parameter.Type);
        end
    end
end

