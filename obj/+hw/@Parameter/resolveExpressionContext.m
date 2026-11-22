function [rewrittenText, context, info, plan] = resolveExpressionContext(expressionText, currentValue, targetParam, siblingsFcn, allParamsFcn, valueFcn)
% [rewrittenText, context, info, plan] = hw.Parameter.resolveExpressionContext(expressionText, currentValue, targetParam, siblingsFcn, allParamsFcn, valueFcn)
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
%   plan          - How the context was built, so a caller that evaluates the
%                   same expression again can rebuild it without resolving
%                   the text a second time (hw.Parameter.evaluateExpression_
%                   does, once per trial):
%       .rewrittenText  as returned
%       .bindings       struct array, one per context variable other than
%                       Value, in the order they were bound: name (the
%                       context field), param (hw.Parameter), prop ('' for
%                       the parameter's value through valueFcn, else the
%                       property read), simpleOnly (true where the variable
%                       is bound only when the value is numeric, logical or
%                       text)
%       .usesAllParams  true when allParamsFcn was consulted
%       .complete       false when building the context failed part way and
%                       was reduced to a warning; such a plan must not be
%                       reused
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
bindings = localEmptyBindings_();
usesAllParams = false;
complete = false;

% Build context: Value holds incoming value; siblings in same module by name.
%
% Only siblings the expression NAMES are read. The context used to hold every
% parameter of the module, and at runtime each of those is a device read
% (valueFcn is p.Value): an expression on a 60-tag RPvds module cost 60 round
% trips -- whole buffers included -- on every trial dispatch, to evaluate
% "StimDelay + 250". The test is a plain identifier scan of the text, with no
% lookarounds: a superset of what the expression can reference, so a sibling
% that shadows a function name is still defined exactly when its name
% appears. The one thing it cannot see is a name built at evaluation time
% (eval(['Fo' 'o'])), which was never a supported way to write one.
context = struct('Value', currentValue);
try
    siblings = siblingsFcn();
    identifiers = unique(regexp(expressionText, '[A-Za-z]\w*', 'match'));
    if ~isempty(siblings) && ~isempty(identifiers)
        varNames = matlab.lang.makeValidName({siblings.Name});
        named = find(ismember(varNames, identifiers));
    else
        varNames = {};
        named = [];
    end
    for idx = named
        sib = siblings(idx);
        if isequal(sib, targetParam)
            continue
        end
        varName = varNames{idx};
        bindings(end+1) = localBinding_(varName, sib, '', true);
        sibVal = valueFcn(sib);
        if isnumeric(sibVal) || islogical(sibVal) || ischar(sibVal) || isstring(sibVal)
            context.(varName) = sibVal;
            siblingMap(end+1) = struct('varName', varName, 'param', sib);
        end
    end

    % Both rewrite passes act on Name.Name tokens only, so an expression with
    % none skips them -- and skips gathering every parameter of every
    % interface, which is what allParamsFcn does at runtime. A dot operator
    % (A.*B, A.^2) is not such a token: what follows its dot is not a letter.
    if ~isempty(regexp(expressionText, '(?<!\.)\<[A-Za-z]\w*\.[A-Za-z]\w*\>', 'once'))
        % Collect all parameters across the interface once for both rewrite passes
        allParams = allParamsFcn();
        usesAllParams = true;

        % Rewrite property access (Param.Prop, ModuleName.Param.Prop) before module
        % references so that 3-level chains are not consumed by the 2-level rewriter.
        [expressionText, context, propRefs, propUnresolved, propBinds] = ...
            localRewritePropertyRefs_(siblings, allParams, expressionText, context, valueFcn);

        % Rewrite qualified value references (ModuleName.ParamName) to aliases
        [expressionText, context, qualRefs, qualUnresolved, qualBinds] = ...
            localRewriteQualifiedRefs_(allParams, expressionText, context, valueFcn);

        refs = [refs, propRefs, qualRefs];
        unresolved = [unresolved, propUnresolved, qualUnresolved];
        bindings = [bindings, propBinds, qualBinds];
    end
    complete = true;
catch ME
    vprintf(0, 1, 'hw:Parameter:ExpressionContextWarning: could not fully build context for "%s": %s', ...
        targetParam.Name, ME.message);
end

rewrittenText = expressionText;

if nargout > 3
    plan = struct('rewrittenText', rewrittenText, 'bindings', bindings, ...
        'usesAllParams', usesAllParams, 'complete', complete);
end

if nargout > 2
    % Report which siblings the (rewritten) expression actually references.
    % A name followed by a dot is a reference unless a LETTER follows the
    % dot: "A.B" is someone else's token, but "A.*B", "A./B" and "A.^2" are A
    % under a dot operator. Refusing any dot dropped those from the report,
    % so orderByDependencies never saw the dependency and the expression
    % evaluated against the previous trial's value.
    for idx = 1:numel(siblingMap)
        pattern = ['(?<!\.)\<' regexptranslate('escape', siblingMap(idx).varName) '\>(?!\.[A-Za-z])'];
        if ~isempty(regexp(rewrittenText, pattern, 'once'))
            refs(end+1) = localMakeRef_(siblingMap(idx).varName, 'sibling', '', ...
                siblingMap(idx).param.Name, '', siblingMap(idx).param, ...
                context.(siblingMap(idx).varName));
        end
    end

    info = struct( ...
        'references', refs, ...
        'unresolvedQualified', {unresolved}, ...
        'usesValueVariable', ~isempty(regexp(rewrittenText, '(?<!\.)\<Value\>(?!\.[A-Za-z])', 'once')));
end


function refs = localEmptyRefs_()
    refs = struct('token', {}, 'kind', {}, 'moduleName', {}, 'paramName', {}, ...
        'propName', {}, 'param', {}, 'value', {});


function b = localEmptyBindings_()
    b = struct('name', {}, 'param', {}, 'prop', {}, 'simpleOnly', {});


function b = localBinding_(name, param, prop, simpleOnly)
% One context variable and where its value comes from (see plan.bindings).
    b = struct('name', name, 'param', param, 'prop', prop, 'simpleOnly', simpleOnly);


function ref = localMakeRef_(token, kind, moduleName, paramName, propName, param, value)
% value is wrapped in a cell so cell-valued properties (e.g. Values) stay scalar
    ref = struct('token', token, 'kind', kind, 'moduleName', moduleName, ...
        'paramName', paramName, 'propName', propName, 'param', param, 'value', {{value}});


function [expressionText, context, refs, unresolved, binds] = localRewritePropertyRefs_(siblings, allParams, expressionText, context, valueFcn)
% Rewrite Param.Prop and ModuleName.Param.Prop tokens to flat aliases and
% populate context with the referenced property value.
% Recognized properties: Min, Max, Values, Value.
% 3-level (cross-module) patterns are processed first to prevent the
% 2-level rewriter from consuming the ModuleName.Param prefix.
    ALLOWED_PROPS = {'Min', 'Max', 'Values', 'Value'};
    refs = localEmptyRefs_();
    unresolved = {};
    binds = localEmptyBindings_();

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
        binds(end+1) = localBinding_(alias, matches(1), propName, false);
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
        binds(end+1) = localBinding_(alias, siblings(sibIdx), propName, false);
        if strcmp(propName, 'Value')
            context.(alias) = valueFcn(siblings(sibIdx));
        else
            context.(alias) = siblings(sibIdx).(propName);
        end
        refs(end+1) = localMakeRef_(sprintf('%s.%s', paramName, propName), ...
            'sibProp', '', paramName, propName, siblings(sibIdx), context.(alias));
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end


function [expressionText, context, refs, unresolved, binds] = localRewriteQualifiedRefs_(allParams, expressionText, context, valueFcn)
% Rewrite ModuleName.ParamName tokens in expressionText to valid variable aliases
% and populate context with the current value of each referenced cross-module parameter.
    refs = localEmptyRefs_();
    unresolved = {};
    binds = localEmptyBindings_();

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
        binds(end+1) = localBinding_(alias, param, '', true);
        paramVal = valueFcn(param);
        if isnumeric(paramVal) || islogical(paramVal) || ischar(paramVal) || isstring(paramVal)
            context.(alias) = paramVal;
        end
        refs(end+1) = localMakeRef_(sprintf('%s.%s', moduleName, paramName), ...
            'qualified', moduleName, paramName, '', param, paramVal);
        expressionText = [expressionText(1:starts(idx)-1), alias, expressionText(ends(idx)+1:end)];
    end
