function result = evaluateParameterExpression(obj, targetParameter, expressionText)
    % evaluateParameterExpression(obj, targetParameter, expressionText)
    % Evaluate one parameter expression against the current parameter set.
    % Rejects assignments and references to parameters that cannot
    % participate in numeric expressions.
    %
    % Parameters:
    % 	targetParameter	- Parameter receiving the evaluated value.
    % 	expressionText	- MATLAB expression string stored on hw.Parameter.Expression.
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
    expressionText = localRewritePropertyRefs_(obj, targetParameter, expressionText);
    expressionText = localRewriteQualifiedReferences_(obj, targetParameter, expressionText);
    context = obj.buildExpressionContext(targetParameter);

    names = fieldnames(context);
    for idx = 1:numel(names)
        eval(sprintf('%s = context.(names{%d});', names{idx}, idx)); %#ok<EVLDIR>
    end
    result = eval(expressionText); %#ok<EVLDIR>
end

function expressionText = localRewritePropertyRefs_(obj, targetParameter, expressionText)
% Rewrite Param.Prop and ModuleName.Param.Prop tokens to flat aliases.
% Recognized properties: Min, Max, Values, Value.
% 3-level patterns are processed first to prevent the 2-level rewriter
% from consuming the ModuleName.Param prefix.
    ALLOWED_PROPS = {'Min', 'Max', 'Values', 'Value'};
    allParameters = obj.getAllParameters();
    siblings = targetParameter.Module.Parameters;
    sibNames = arrayfun(@(p) p.Name, siblings, 'UniformOutput', false);

    % Pass 1: 3-level cross-module  ModuleName.Param.Prop
    [tokens, starts, ends] = regexp(expressionText, ...
        '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\.([A-Za-z]\w*)\>', ...
        'tokens', 'start', 'end');

    for idx = numel(starts):-1:1
        token = tokens{idx};
        moduleName = token{1};
        paramName  = token{2};
        propName   = token{3};

        if ~ismember(propName, ALLOWED_PROPS)
            continue
        end

        matchMask = arrayfun(@(p) strcmp(p.Module.Name, moduleName) && strcmp(p.Name, paramName), allParameters);
        matches = allParameters(matchMask);
        if isempty(matches)
            continue
        end

        baseAlias = obj.getQualifiedExpressionAlias(matches(1));
        alias = matlab.lang.makeValidName(sprintf('%s_%s', baseAlias, propName));
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end

    % Pass 2: 2-level sibling  Param.Prop
    [tokens, starts, ends] = regexp(expressionText, ...
        '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\>', ...
        'tokens', 'start', 'end');

    for idx = numel(starts):-1:1
        token = tokens{idx};
        paramName = token{1};
        propName  = token{2};

        if ~ismember(propName, ALLOWED_PROPS)
            continue
        end

        sibIdx = find(strcmp(sibNames, paramName), 1);
        if isempty(sibIdx)
            continue
        end

        alias = matlab.lang.makeValidName(sprintf('exprSibProp_%s_%s', paramName, propName));
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end
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

