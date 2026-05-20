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
%   - Parameter properties via Param.Prop (sibling) or ModuleName.Param.Prop
%     (cross-module), where Prop is one of: Min, Max, Values, Value.
%     These are rewritten to flat aliases before evaluation.
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

    % Collect all parameters across the interface once for both rewrite passes
    allParams = localCollectAllParams_(thisModule);

    % Rewrite property access (Param.Prop, ModuleName.Param.Prop) before module
    % references so that 3-level chains are not consumed by the 2-level rewriter.
    [expressionText, context] = localRewritePropertyRefs_(siblings, allParams, expressionText, context);

    % Rewrite qualified value references (ModuleName.ParamName) to aliases
    [expressionText, context] = localRewriteQualifiedRefs_(allParams, expressionText, context);
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


function allParams = localCollectAllParams_(thisModule)
% Collect all hw.Parameter objects across all modules of the parent interface.
% Returns an empty array if the interface is not accessible.
    allParams = hw.Parameter.empty(1, 0);
    try
        allModules = thisModule.parent.Module;
        for mIdx = 1:numel(allModules)
            mod = allModules(mIdx);
            if ~isempty(mod.Parameters)
                allParams = [allParams, mod.Parameters];
            end
        end
    catch
    end


function [expressionText, context] = localRewritePropertyRefs_(siblings, allParams, expressionText, context)
% Rewrite Param.Prop and ModuleName.Param.Prop tokens to flat aliases and
% populate context with the referenced property value.
% Recognized properties: Min, Max, Values, Value.
% 3-level (cross-module) patterns are processed first to prevent the
% 2-level rewriter from consuming the ModuleName.Param prefix.
    ALLOWED_PROPS = {'Min', 'Max', 'Values', 'Value'};

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

        matchMask = arrayfun(@(p) strcmp(p.Module.Name, moduleName) && strcmp(p.Name, paramName), allParams);
        matches = allParams(matchMask);
        if isempty(matches)
            continue
        end

        alias = matlab.lang.makeValidName(sprintf('exprModProp_%s_%s_%s', moduleName, paramName, propName));
        context.(alias) = matches(1).(propName);
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end

    % Pass 2: 2-level sibling  Param.Prop
    sibNames = arrayfun(@(p) p.Name, siblings, 'UniformOutput', false);

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
        context.(alias) = siblings(sibIdx).(propName);
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end


function [expressionText, context] = localRewriteQualifiedRefs_(allParams, expressionText, context)
% Rewrite ModuleName.ParamName tokens in expressionText to valid variable aliases
% and populate context with the current Value of each referenced cross-module parameter.
    [tokens, starts, ends] = regexp(expressionText, ...
        '(?<!\.)\<([A-Za-z]\w*)\.([A-Za-z]\w*)\>', 'tokens', 'start', 'end');

    if isempty(tokens)
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
