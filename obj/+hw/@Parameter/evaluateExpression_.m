function result = evaluateExpression_(obj, currentValue)
% result = evaluateExpression_(obj, currentValue)
% Evaluate obj.Expression to derive a new parameter value.
% Called after randomization and before EvaluatorFcn in set.Value.
%
% The expression runs with:
%   - Value  - the incoming currentValue (output variable).
%   - Sibling parameter names (same module) as variables with their current Value.
%   - Cross-module parameters available as ModuleName.ParamName syntax,
%     which is rewritten to a valid alias before evaluation.
%
% Parameters:
%   currentValue - The incoming value after randomization.
%
% Returns:
%   result - The value of `Value` after expression evaluation.
expressionText = strtrim(char(obj.Expression));
if isempty(expressionText)
    result = currentValue;
    return
end

if contains(expressionText, ';')
    error('hw:Parameter:ExpressionMultiStatement', ...
        'Expression for parameter "%s" must be a single statement.', obj.Name);
end

% Build context: Value holds incoming value; siblings in same module by name
context = struct('Value', currentValue);
try
    thisModule = obj.Module;
    siblings = thisModule.Parameters;
    for idx = 1:numel(siblings)
        sib = siblings(idx);
        if isequal(sib, obj)
            continue
        end
        varName = matlab.lang.makeValidName(sib.Name);
        sibVal = sib.Value;
        if isnumeric(sibVal) || islogical(sibVal) || ischar(sibVal) || isstring(sibVal)
            context.(varName) = sibVal;
        end
    end

    % Rewrite qualified references (ModuleName.ParamName) to aliases
    [expressionText, context] = localRewriteQualifiedRefs_(obj, thisModule, expressionText, context);
catch ME
    vprintf(0, 1, 'hw:Parameter:ExpressionContextWarning: could not fully build context for "%s": %s', ...
        obj.Name, ME.message);
end

% Load context variables into local workspace
names = fieldnames(context);
for idx = 1:numel(names)
    eval([names{idx} ' = context.(names{idx});']); %#ok<EVLDIR>
end

% Evaluate; expression may assign to Value or just produce a result
Value = currentValue; %#ok<NASGU>
try
    exprResult__ = eval(expressionText); %#ok<EVLDIR,NASGU>
catch ME
    error('hw:Parameter:ExpressionError', ...
        'Expression evaluation failed for parameter "%s": %s', obj.Name, ME.message);
end

result = Value;


function [expressionText, context] = localRewriteQualifiedRefs_(obj, thisModule, expressionText, context)
% Rewrite ModuleName.ParamName tokens in expressionText to valid variable aliases
% and populate context with the current Value of each referenced cross-module parameter.
    [tokens, starts, ends] = regexp(expressionText, ...
        '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\>', 'tokens', 'start', 'end');

    if isempty(tokens)
        return
    end

    % Collect all parameters across the interface (if accessible)
    allParams = hw.Parameter.empty(1, 0);
    try
        allModules = thisModule.parent.Module;
        for mIdx = 1:numel(allModules)
            mod = allModules(mIdx);
            if ~isempty(mod.Parameters)
                allParams = [allParams, mod.Parameters]; %#ok<AGROW>
            end
        end
    catch
        return
    end

    for idx = numel(starts):-1:1
        token = tokens{idx};
        moduleName = token{1};
        paramName  = token{2};

        matchMask = arrayfun(@(p) strcmp(p.Module.Name, moduleName) && strcmp(p.Name, paramName), allParams);
        matches = allParams(matchMask);
        if isempty(matches)
            continue
        end

        param = matches(1);
        alias = matlab.lang.makeValidName(sprintf('exprMod_%s_%s', moduleName, paramName));
        paramVal = param.Value;
        if isnumeric(paramVal) || islogical(paramVal) || ischar(paramVal) || isstring(paramVal)
            context.(alias) = paramVal;
        end
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end
