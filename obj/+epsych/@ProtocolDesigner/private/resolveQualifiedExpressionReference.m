function parameter = resolveQualifiedExpressionReference(obj, targetParameter, moduleName, parameterName)
    parameters = obj.getAllParameters();
    matchMask = arrayfun(@(p) strcmp(p.Module.Name, moduleName) && strcmp(p.Name, parameterName), parameters);
    matches = parameters(matchMask);

    if isempty(matches)
        error('Unknown parameter reference %s.%s.', moduleName, parameterName);
    end

    nonTargetMask = ~arrayfun(@(p) isequal(p, targetParameter), matches);
    matches = matches(nonTargetMask);
    if isempty(matches)
        error('Expression cannot reference %s.%s recursively.', moduleName, parameterName);
    end

    if numel(matches) > 1
        error('Expression reference %s.%s is ambiguous because multiple modules share that name.', ...
            moduleName, parameterName);
    end

    parameter = matches(1);
end