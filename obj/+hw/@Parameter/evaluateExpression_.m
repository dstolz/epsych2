function result = evaluateExpression_(obj, currentValue)
% result = evaluateExpression_(obj, currentValue)
% Evaluate obj.Expression to derive a new parameter value.
% Called after randomization and before EvaluatorFcn in set.Value.
%
% The expression runs with:
%   - Value  - the incoming currentValue (after randomization).
%   - Sibling parameter names (same module) as variables with their current Value.
%   - Cross-module parameters available as ModuleName.ParamName syntax,
%     which is rewritten to a valid alias before evaluation.
%   - Parameter properties via Param.Prop (sibling) or ModuleName.Param.Prop
%     (cross-module), where Prop is one of: Min, Max, Values, Value.
%     These are rewritten to flat aliases before evaluation.
%
% For 'String' and 'StimType' parameters the expression result is a 1-based
% index into obj.Values and the selected item is returned; for every other
% type the result is the value itself.
%
% The reference resolution and evaluation are shared with design-time tools
% via hw.Parameter.resolveExpressionContext / evalExpressionInContext; this
% wrapper supplies the live runtime lookups (current parameter Values).
%
% Parameters:
%   currentValue - The incoming value after randomization.
%
% Returns:
%   result - The expression's result.
expressionText = strtrim(char(obj.Expression));
if isempty(expressionText)
    result = currentValue;
    return
end

selectsIndex = hw.Parameter.expressionSelectsIndex(obj.Type);

% Multi-level parameters carry their Expression only as a design-time level
% generator (e.g. "[0 1 2]"), which compile() has already expanded into the
% discrete trial levels held in obj.Values. At runtime the dispatcher assigns
% one level per trial, so re-evaluating the expression here would overwrite
% that per-trial value with the full level set (and, for scalar hardware tags,
% fail to write). Skip runtime evaluation when more than one level is defined.
% Index-selecting types are exempt: there Values is the item list the
% expression picks from, so many items keep the expression live.
if ~selectsIndex && numel(obj.Values) > 1
    result = currentValue;
    return
end

% Resolving the text -- finding which parameters it names, rewriting
% Module.Parameter tokens to aliases -- gives the same answer on every trial,
% and it was most of what an Expression cost: on the rig two expressions took
% a third of a trial's whole dispatch-write time, nearly all of it here and
% not in reading the values. So the resolver's answer is kept on the
% parameter (ExpressionPlan_) and only the VALUES are read again. Every value
% an expression sees is still read at evaluation, from the same place.
%
% The plan is used only while it provably still describes this expression:
% the same text, the same sibling objects in the same order, and, where the
% text reaches outside the module, the same number of parameters in scope.
% Anything else -- an edited Expression, a parameter added by a selector, a
% module rebuilt on connect -- resolves afresh.
planned = false;
plan = obj.ExpressionPlan_;
if localPlanFits_(obj, plan, expressionText)
    try
        context = localContextFromPlan_(plan, currentValue);
        rewrittenText = plan.rewrittenText;
        planned = true;
    catch
        % A value could not be read. The resolver below reads again and
        % reduces the failure to its logged warning and a partial context,
        % exactly as it always has.
    end
end

if ~planned
    % Lookups run inside the resolver's try/catch, so a failure while
    % gathering siblings or interface parameters degrades to a partial
    % context with a logged warning rather than aborting evaluation.
    [rewrittenText, context, ~, plan] = hw.Parameter.resolveExpressionContext( ...
        expressionText, currentValue, obj, ...
        @() obj.Module.Parameters, ...
        @() localCollectAllParams_(obj.Module), ...
        @localContextValue_);
    obj.ExpressionPlan_ = localKeepPlan_(obj, plan, expressionText);
end

result = hw.Parameter.evalExpressionInContext(rewrittenText, context, obj.Name);

if selectsIndex
    result = hw.Parameter.selectValueByIndex(result, obj.Values, obj.Name);
end


function v = localContextValue_(p)
% Value of one parameter as seen by an expression. resolveExpressionContext
% reads EVERY sibling, referenced or not, so this runs against parameters the
% expression never mentions. A write-only parameter has nothing to read back:
% get.Value logs a critical record and returns NaN, which would both flood the
% log on every dispatch and poison the expression. Fall back to its first
% design-time level, the same stand-in analyzeExpressions/orderByDependencies
% and the Check Calculations tools use, so runtime and preview agree.
    if isequal(p.Access, 'Write')
        if isempty(p.Values)
            v = NaN;
        else
            v = p.Values{1};
        end
        return
    end
    v = p.Value;


function tf = localPlanFits_(obj, plan, expressionText)
% Whether a kept plan still describes this parameter's expression.
    tf = false;
    if ~isstruct(plan) || ~strcmp(plan.text, expressionText)
        return
    end
    siblings = obj.Module.Parameters;
    if numel(siblings) ~= numel(plan.siblings) || ~all(siblings == plan.siblings)
        return
    end
    if plan.usesAllParams && localCountAllParams_(obj.Module) ~= plan.numAll
        return
    end
    B = plan.bindings;
    for k = 1:numel(B)
        if ~isvalid(B(k).param)
            return
        end
    end
    tf = true;


function kept = localKeepPlan_(obj, plan, expressionText)
% The resolver's plan with what localPlanFits_ checks it against, or [] when
% the resolver could not finish: a partial plan must not be reused.
    kept = [];
    if ~plan.complete
        return
    end
    kept = plan;
    kept.text = expressionText;
    kept.siblings = obj.Module.Parameters;
    kept.numAll = 0;
    if plan.usesAllParams
        % NaN (the scope could not be counted) equals nothing, so such a
        % plan is never reused.
        kept.numAll = localCountAllParams_(obj.Module);
    end


function context = localContextFromPlan_(plan, currentValue)
% The context resolveExpressionContext would build, from a kept plan: the
% same variables, bound in the same order, by the same rules.
    context = struct('Value', currentValue);
    B = plan.bindings;
    for k = 1:numel(B)
        if isempty(B(k).prop) || strcmp(B(k).prop, 'Value')
            v = localContextValue_(B(k).param);
        else
            v = B(k).param.(B(k).prop);
        end
        if B(k).simpleOnly && ~(isnumeric(v) || islogical(v) || ischar(v) || isstring(v))
            continue
        end
        context.(B(k).name) = v;
    end


function n = localCountAllParams_(thisModule)
% How many parameters localCollectAllParams_ would return, without gathering
% them. NaN when the scope cannot be walked.
    n = 0;
    try
        iface = thisModule.parent;
        if ~isempty(iface.Runtime) && isvalid(iface.Runtime)
            interfaces = iface.Runtime.Interfaces;
            for a = 1:numel(interfaces)
                modules = interfaces(a).Module;
                for b = 1:numel(modules)
                    n = n + numel(modules(b).Parameters);
                end
            end
        else
            modules = iface.Module;
            for b = 1:numel(modules)
                n = n + numel(modules(b).Parameters);
            end
        end
    catch
        n = NaN;
    end


function allParams = localCollectAllParams_(thisModule)
% Collect all hw.Parameter objects accessible for expression evaluation.
% Prefers the full runtime parameter set (all interfaces) when available;
% falls back to modules of the same interface only.
    allParams = hw.Parameter.empty(1, 0);
    try
        iface = thisModule.parent;
        if ~isempty(iface.Runtime) && isvalid(iface.Runtime)
            % Collect across all interfaces registered with the runtime
            rt = iface.Runtime;
            for mIdx = 1:numel(rt.Interfaces)
                allModules = rt.Interfaces(mIdx).Module;
                for modIdx = 1:numel(allModules)
                    if ~isempty(allModules(modIdx).Parameters)
                        allParams = [allParams, allModules(modIdx).Parameters];
                    end
                end
            end
        else
            % No runtime available; collect from same interface only
            allModules = iface.Module;
            for mIdx = 1:numel(allModules)
                mod = allModules(mIdx);
                if ~isempty(mod.Parameters)
                    allParams = [allParams, mod.Parameters];
                end
            end
        end
    catch
    end
