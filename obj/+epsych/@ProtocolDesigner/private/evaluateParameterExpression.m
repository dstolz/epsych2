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

    obj.validateExpressionReferences(targetParameter, expressionText);
    context = obj.buildExpressionContext(targetParameter);

    if ~isempty(regexp(expressionText, '(?<![<>=~])=(?![=])', 'once'))
        error('Assignments are not allowed in expressions.');
    end
    if contains(expressionText, ';')
        error('Only a single MATLAB expression is allowed.');
    end

    names = fieldnames(context);
    for idx = 1:numel(names)
        eval(sprintf('%s = context.(names{%d});', names{idx}, idx)); %#ok<EVLDIR>
    end
    result = eval(expressionText); %#ok<EVLDIR>
end

