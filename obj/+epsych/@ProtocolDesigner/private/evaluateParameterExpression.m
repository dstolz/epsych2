function result = evaluateParameterExpression(obj, targetParameter, expressionText)
    % evaluateParameterExpression(obj, targetParameter, expressionText)
    % Evaluate one parameter expression against the current parameter set.
    % Rejects assignments and references to parameters that cannot
    % participate in numeric expressions.
    %
    % Parameters:
    % 	targetParameter	- Parameter receiving the evaluated value.
    % 	expressionText	- MATLAB expression string stored in UserData.Expression.
    %
    % Returns:
    % 	result	- Numeric or logical expression result before type normalization.
    expressionText = strtrim(char(string(expressionText)));
    if isempty(expressionText)
        error('Expression cannot be empty.');
    end

    if ~isempty(regexp(expressionText, '(?<![<>=~])=(?![=])', 'once'))
        error('Assignments are not allowed in expressions.');
    end
    if contains(expressionText, ';')
        error('Only a single MATLAB expression is allowed.');
    end

    obj.validateExpressionReferences(targetParameter, expressionText);
    expressionText = localRewriteQualifiedReferences_(obj, targetParameter, expressionText);
    context = obj.buildExpressionContext(targetParameter);

    names = fieldnames(context);
    for idx = 1:numel(names)
        eval(sprintf('%s = context.(names{%d});', names{idx}, idx)); %#ok<EVLDIR>
    end
    result = eval(expressionText); %#ok<EVLDIR>
end

function expressionText = localRewriteQualifiedReferences_(obj, targetParameter, expressionText)
    [tokens, starts, ends] = regexp(expressionText, '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\>', ...
        'tokens', 'start', 'end');

    for idx = numel(starts):-1:1
        token = tokens{idx};
        parameter = obj.resolveQualifiedExpressionReference(targetParameter, token{1}, token{2});
        alias = obj.getQualifiedExpressionAlias(parameter);
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end
end

