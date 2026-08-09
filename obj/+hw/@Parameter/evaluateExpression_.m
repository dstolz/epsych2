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

% Multi-level parameters carry their Expression only as a design-time level
% generator (e.g. "[0 1 2]"), which compile() has already expanded into the
% discrete trial levels held in obj.Values. At runtime the dispatcher assigns
% one level per trial, so re-evaluating the expression here would overwrite
% that per-trial value with the full level set (and, for scalar hardware tags,
% fail to write). Skip runtime evaluation when more than one level is defined.
if numel(obj.Values) > 1
    result = currentValue;
    return
end

% Lookups run inside the resolver's try/catch, so a failure while gathering
% siblings or interface parameters degrades to a partial context with a
% logged warning rather than aborting evaluation.
[rewrittenText, context] = hw.Parameter.resolveExpressionContext( ...
    expressionText, currentValue, obj, ...
    @() obj.Module.Parameters, ...
    @() localCollectAllParams_(obj.Module), ...
    @(p) p.Value);

result = hw.Parameter.evalExpressionInContext(rewrittenText, context, obj.Name);


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
