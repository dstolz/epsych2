function order = orderByDependencies(dispatchParams, allParams)
% order = hw.Parameter.orderByDependencies(dispatchParams, allParams)
% Permutation of dispatchParams placing expression parameters after the
% parameters whose values their Expressions read.
%
% The per-trial dispatcher (epsych.Runtime.dispatchNextTrial) assigns
% parameter values in this order. A parameter whose Expression reads another
% dispatched parameter's value must be assigned after it, or the expression
% evaluates against the previous trial's value — stale by one trial whenever
% the referenced parameter is randomized (isRandom) or mutated between
% trials (staircases, trial selectors).
%
% Ordering rules:
%   - Parameters without value-reading references keep their relative order.
%   - Expression parameters sort after every dispatched parameter whose
%     *value* they read (sibling/qualified references, or property
%     references to Value). Min/Max/Values property references impose no
%     ordering because per-trial dispatch never writes those properties.
%   - Multi-level parameters (numel(Values) > 1) are treated as plain: the
%     runtime skips their expression (design-time level generator only).
%   - Self-references impose no ordering (documented previous-value
%     semantics).
%   - Reference cycles fall back to declared order for their members;
%     Protocol.expressionIssues_ warns about cycles separately.
%
% Parameters:
%   dispatchParams - hw.Parameter array in declared (compiled) dispatch order.
%   allParams      - hw.Parameter array forming the reference-resolution
%                    scope (every parameter of every module), matching the
%                    runtime evaluator's scope.
%
% Returns:
%   order - 1xN permutation indices into dispatchParams.

n = numel(dispatchParams);
order = 1:n;
if n < 2
    return
end

% deps{i}: indices into dispatchParams whose values parameter i's expression reads
deps = cell(1, n);
for i = 1:n
    p = dispatchParams(i);
    exprText = strtrim(char(p.Expression));

    % Mirror hw.Parameter.evaluateExpression_: empty expressions and
    % multi-level parameters never evaluate at runtime.
    if isempty(exprText) || numel(p.Values) > 1
        continue
    end

    try
        [~, ~, info] = hw.Parameter.resolveExpressionContext( ...
            exprText, NaN, p, ...
            @() p.Module.Parameters, ...
            @() allParams, ...
            @(q) localDesignValue_(q));
    catch
        % Unresolvable expressions keep declared order; runtime evaluation
        % surfaces the error itself.
        continue
    end

    d = [];
    for r = 1:numel(info.references)
        ref = info.references(r);
        q = ref.param;
        if isempty(q) || q == p
            continue
        end
        readsValue = ismember(ref.kind, {'sibling', 'qualified'}) || strcmp(ref.propName, 'Value');
        if ~readsValue
            continue
        end
        j = find(dispatchParams == q, 1);
        if ~isempty(j) && j ~= i
            d(end+1) = j;
        end
    end
    deps{i} = unique(d);
end

% Stable topological sort (Kahn): among ready nodes always emit the lowest
% declared index, so dependency-free parameters keep their relative order.
remaining = true(1, n);
sorted = zeros(1, 0);
while any(remaining)
    ready = find(remaining & cellfun(@(d) ~any(remaining(d)), deps));
    if isempty(ready)
        % Cycle: emit the remaining members in declared order
        sorted = [sorted, find(remaining)];
        break
    end
    sorted(end+1) = ready(1);
    remaining(ready(1)) = false;
end
order = sorted;
end


function v = localDesignValue_(q)
% Placeholder value for reference resolution: first design-time level.
% Never reads q.Value, which can trigger a live hardware read.
if ~isempty(q.Values)
    v = q.Values{1};
else
    v = NaN;
end
end
