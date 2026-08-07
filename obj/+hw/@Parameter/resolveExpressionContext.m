function [rewrittenText, context, info] = resolveExpressionContext(expressionText, currentValue, targetParam, siblingsFcn, allParamsFcn, valueFcn)
% [rewrittenText, context, info] = hw.Parameter.resolveExpressionContext(expressionText, currentValue, targetParam, siblingsFcn, allParamsFcn, valueFcn)
% Resolve parameter references in an Expression and build its eval context.
%
% Shared core of runtime and design-time expression evaluation. Rewrites
% property references (Param.Prop, ModuleName.Param.Prop) and qualified value
% references (ModuleName.ParamName) to flat aliases and collects a context
% struct mapping variable names to values. Every parameter *value* read goes
% through valueFcn so callers control where values come from: the runtime
% passes @(p) p.Value, while the Protocol Designer's calculation checker
% passes a lookup into simulated per-trial values.
%
% Parameters:
%   expressionText - char, trimmed non-empty expression text.
%   currentValue   - Incoming value; exposed to the expression as `Value`.
%   targetParam    - hw.Parameter owning the expression (skipped in the
%                    sibling context; named in error messages).
%   siblingsFcn    - @() returning the hw.Parameter array of same-module
%                    siblings (including targetParam; it is skipped here).
%   allParamsFcn   - @() returning the hw.Parameter array searched for
%                    qualified ModuleName.ParamName references.
%   valueFcn       - @(hw.Parameter) returning that parameter's value.
%
% Returns:
%   rewrittenText - Expression with references replaced by context aliases.
%   context       - struct of variables to inject into the eval workspace.
%   info          - Reference diagnostics for validation/preview tools:
%       .references          struct array: token, kind ('sibling'|'qualified'|
%                            'sibProp'|'crossProp'), moduleName, paramName,
%                            propName, param (hw.Parameter or []), value
%                            (1x1 cell wrapping the resolved value)
%       .unresolvedQualified cellstr of Name.Name tokens that matched the
%                            reference syntax but resolved to no parameter
%                            (left verbatim in the text, as at runtime)
%       .usesValueVariable   true when the expression references `Value`
%
% Behavior is identical to the historical runtime evaluator: ';' raises
% hw:Parameter:ExpressionMultiStatement, and any failure while building the
% context is reduced to a logged warning so evaluation proceeds with a
% partial context.

if contains(expressionText, ';')
    error('hw:Parameter:ExpressionMultiStatement', ...
        'Expression for parameter "%s" must be a single statement.', targetParam.Name);
end

refs = localEmptyRefs_();
unresolved = {};
siblingMap = struct('varName', {}, 'param', {});

% Build context: Value holds incoming value; siblings in same module by name
context = struct('Value', currentValue);
try
    siblings = siblingsFcn();
    for idx = 1:numel(siblings)
        sib = siblings(idx);
        if isequal(sib, targetParam)
            continue
        end
        varName = matlab.lang.makeValidName(sib.Name);
        sibVal = valueFcn(sib);
        if isnumeric(sibVal) || islogical(sibVal) || ischar(sibVal) || isstring(sibVal)
            context.(varName) = sibVal;
            siblingMap(end+1) = struct('varName', varName, 'param', sib);
        end
    end

    % Collect all parameters across the interface once for both rewrite passes
    allParams = allParamsFcn();

    % Rewrite property access (Param.Prop, ModuleName.Param.Prop) before module
    % references so that 3-level chains are not consumed by the 2-level rewriter.
    [expressionText, context, propRefs, propUnresolved] = ...
        localRewritePropertyRefs_(siblings, allParams, expressionText, context, valueFcn);

    % Rewrite qualified value references (ModuleName.ParamName) to aliases
    [expressionText, context, qualRefs, qualUnresolved] = ...
        localRewriteQualifiedRefs_(allParams, expressionText, context, valueFcn);

    refs = [refs, propRefs, qualRefs];
    unresolved = [unresolved, propUnresolved, qualUnresolved];
catch ME
    vprintf(0, 1, 'hw:Parameter:ExpressionContextWarning: could not fully build context for "%s": %s', ...
        targetParam.Name, ME.message);
end

rewrittenText = expressionText;

if nargout > 2
    % Report which siblings the (rewritten) expression actually references
    for idx = 1:numel(siblingMap)
        pattern = ['(?<!\.)\<' regexptranslate('escape', siblingMap(idx).varName) '\>(?!\.)'];
        if ~isempty(regexp(rewrittenText, pattern, 'once'))
            refs(end+1) = localMakeRef_(siblingMap(idx).varName, 'sibling', '', ...
                siblingMap(idx).param.Name, '', siblingMap(idx).param, ...
                context.(siblingMap(idx).varName));
        end
    end

    info = struct( ...
        'references', refs, ...
        'unresolvedQualified', {unresolved}, ...
        'usesValueVariable', ~isempty(regexp(rewrittenText, '(?<!\.)\<Value\>(?!\.)', 'once')));
end


function refs = localEmptyRefs_()
    refs = struct('token', {}, 'kind', {}, 'moduleName', {}, 'paramName', {}, ...
        'propName', {}, 'param', {}, 'value', {});


function ref = localMakeRef_(token, kind, moduleName, paramName, propName, param, value)
% value is wrapped in a cell so cell-valued properties (e.g. Values) stay scalar
    ref = struct('token', token, 'kind', kind, 'moduleName', moduleName, ...
        'paramName', paramName, 'propName', propName, 'param', param, 'value', {{value}});


function [expressionText, context, refs, unresolved] = localRewritePropertyRefs_(siblings, allParams, expressionText, context, valueFcn)
% Rewrite Param.Prop and ModuleName.Param.Prop tokens to flat aliases and
% populate context with the referenced property value.
% Recognized properties: Min, Max, Values, Value.
% 3-level (cross-module) patterns are processed first to prevent the
% 2-level rewriter from consuming the ModuleName.Param prefix.
    ALLOWED_PROPS = {'Min', 'Max', 'Values', 'Value'};
    refs = localEmptyRefs_();
    unresolved = {};

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
            unresolved{end+1} = sprintf('%s.%s.%s', moduleName, paramName, propName);
            continue
        end

        alias = matlab.lang.makeValidName(sprintf('exprModProp_%s_%s_%s', moduleName, paramName, propName));
        if strcmp(propName, 'Value')
            context.(alias) = valueFcn(matches(1));
        else
            context.(alias) = matches(1).(propName);
        end
        refs(end+1) = localMakeRef_(sprintf('%s.%s.%s', moduleName, paramName, propName), ...
            'crossProp', moduleName, paramName, propName, matches(1), context.(alias));
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
        if strcmp(propName, 'Value')
            context.(alias) = valueFcn(siblings(sibIdx));
        else
            context.(alias) = siblings(sibIdx).(propName);
        end
        refs(end+1) = localMakeRef_(sprintf('%s.%s', paramName, propName), ...
            'sibProp', '', paramName, propName, siblings(sibIdx), context.(alias));
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end


function [expressionText, context, refs, unresolved] = localRewriteQualifiedRefs_(allParams, expressionText, context, valueFcn)
% Rewrite ModuleName.ParamName tokens in expressionText to valid variable aliases
% and populate context with the current value of each referenced cross-module parameter.
    refs = localEmptyRefs_();
    unresolved = {};

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
            unresolved{end+1} = sprintf('%s.%s', moduleName, paramName);
            continue
        end

        param = matches(1);
        alias = matlab.lang.makeValidName(sprintf('exprMod_%s_%s', moduleName, paramName));
        paramVal = valueFcn(param);
        if isnumeric(paramVal) || islogical(paramVal) || ischar(paramVal) || isstring(paramVal)
            context.(alias) = paramVal;
        end
        refs(end+1) = localMakeRef_(sprintf('%s.%s', moduleName, paramName), ...
            'qualified', moduleName, paramName, '', param, paramVal);
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end
