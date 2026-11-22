function smoke_test_expression_plan
% smoke_test_expression_plan
% hw.Parameter keeps how its Expression resolved (ExpressionPlan_) and, from
% the second evaluation on, re-reads only the values. The kept plan must give
% what resolving afresh gives, on every evaluation, and must be dropped the
% moment it stops describing the expression.
%
% Verifies:
%   1) sibling references: every evaluation sees the siblings' CURRENT values
%   2) a qualified Module.Parameter reference, likewise
%   3) property references (Param.Max, Module.Param.Min): a bound edited
%      between evaluations is seen
%   4) a dot operator (A.*3) and the Value variable
%   5) a write-only sibling stands in with its first design level, as before
%   6) an index-selecting (String) parameter still returns the selected item
%   7) editing the Expression text resolves afresh
%   8) a parameter added to the module resolves afresh: a name that did not
%      resolve before now does
%   9) the kept plan and a fresh resolve agree, variable for variable
%  10) (reported, not asserted) what one evaluation costs before and after
%
%   matlab -batch "run('tmp/smoke_test_expression_plan.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_expression_plan ===\n');

P = epsych.Protocol;
M = P.Interfaces(1).Module(1);
modName = M.Name;
assert(isvarname(modName), 'the software module name "%s" cannot be written in an expression', modName);

A = localAdd(M, 'A', 1);
B = localAdd(M, 'B', 2);
T = localAdd(M, 'Target', 0);

% --- 1. siblings --------------------------------------------------------------
T.Expression = "A + B*2";
for k = 1:4
    A.Value = k;
    B.Value = 10 * k;
    T.Value = 0;
    assert(T.Value == k + 20 * k, 'evaluation %d of "A + B*2" gave %g', k, T.Value);
end
fprintf('PASS: 1 sibling values are read at every evaluation\n');

% --- 2. a qualified reference -------------------------------------------------
T.Expression = string(modName) + ".A + 10";
for k = 1:4
    A.Value = 3 * k;
    T.Value = 0;
    assert(T.Value == 3 * k + 10, 'evaluation %d of a qualified reference gave %g', k, T.Value);
end
fprintf('PASS: 2 a Module.Parameter reference is read at every evaluation\n');

% --- 3. property references ---------------------------------------------------
A.Min = 0;  A.Max = 100;  A.Value = 5;
T.Expression = "A.Max - A.Min + " + string(modName) + ".A.Max";
for k = 1:4
    A.Max = 100 + k;
    T.Value = 0;
    assert(T.Value == 2 * (100 + k), 'evaluation %d of a property reference gave %g', k, T.Value);
end
A.Min = -inf;  A.Max = inf;
fprintf('PASS: 3 a bound edited between evaluations is seen\n');

% --- 4. a dot operator, and Value --------------------------------------------
T.Expression = "A.*3 + Value";
for k = 1:4
    A.Value = k;
    T.Value = 100;
    assert(T.Value == 3 * k + 100, 'evaluation %d of "A.*3 + Value" gave %g', k, T.Value);
end
fprintf('PASS: 4 a dot operator and the Value variable\n');

% --- 5. a write-only sibling --------------------------------------------------
W = M.add_parameter('WOnly', 7, Access = 'Write');
T.Expression = "WOnly + 1";
for k = 1:3
    T.Value = 0;
    assert(T.Value == 8, 'a write-only sibling should stand in with its design level (got %g)', T.Value);
end
assert(isvalid(W), 'the write-only parameter went away');
fprintf('PASS: 5 a write-only sibling stands in with its first design level\n');

% --- 6. an index-selecting parameter -----------------------------------------
S = M.add_parameter('Label', 'left', Type = 'String');
S.Values = {'left', 'middle', 'right'};
Sel = localAdd(M, 'Sel', 1);
S.Expression = "Sel";
want = {'left', 'middle', 'right', 'middle'};
pick = [1 2 3 2];
for k = 1:numel(pick)
    Sel.Value = pick(k);
    S.Value = 'left';                    % the incoming value is overridden by the index
    assert(strcmp(char(S.Value), want{k}), 'index %d selected "%s"', pick(k), char(S.Value));
end
fprintf('PASS: 6 a String parameter still returns the selected item\n');

% --- 7. the text edited -------------------------------------------------------
A.Value = 4;  B.Value = 5;
T.Expression = "A + B";
T.Value = 0;  T.Value = 0;
assert(T.Value == 9, 'before the edit: %g', T.Value);
T.Expression = "A - B";
T.Value = 0;
assert(T.Value == -1, 'an edited expression must resolve afresh (got %g)', T.Value);
T.Expression = "A * B";
T.Value = 0;  T.Value = 0;
assert(T.Value == 20, 'and again (got %g)', T.Value);
fprintf('PASS: 7 an edited Expression resolves afresh\n');

% --- 8. a parameter added afterwards -----------------------------------------
T.Expression = "A + Later";
threw = '';
try
    T.Value = 0;
catch ME
    threw = ME.identifier;
end
assert(strcmp(threw, 'hw:Parameter:ExpressionError'), 'an unknown name should fail to evaluate (got "%s")', threw);
Later = localAdd(M, 'Later', 50);
A.Value = 1;
T.Value = 0;
assert(T.Value == 51, 'a name that resolves once its parameter exists (got %g)', T.Value);
Later.Value = 60;
T.Value = 0;
assert(T.Value == 61, 'and is read afresh after that (got %g)', T.Value);
fprintf('PASS: 8 a parameter added to the module resolves afresh\n');

% --- 9. plan against a fresh resolve -----------------------------------------
% The resolver reports how it built its context; rebuilding the context from
% that report must reproduce it.
exprs = ["A + B*2", "A.*3 + Value", string(modName) + ".A + B", ...
    "A.Max - " + string(modName) + ".B.Min + A", "WOnly + Sel"];
A.Min = -5;  A.Max = 40;  B.Min = 1;  A.Value = 2;  B.Value = 3;  Sel.Value = 2;
value = @(p) localValue(p);
for e = exprs
    [text, context, ~, plan] = hw.Parameter.resolveExpressionContext(char(e), 11, T, ...
        @() M.Parameters, @() M.Parameters, value);
    assert(plan.complete, '"%s" did not resolve completely', e);
    assert(strcmp(plan.rewrittenText, text), 'the plan and the resolver disagree on the text of "%s"', e);
    rebuilt = struct('Value', 11);
    for b = plan.bindings
        if isempty(b.prop) || strcmp(b.prop, 'Value')
            v = value(b.param);
        else
            v = b.param.(b.prop);
        end
        if b.simpleOnly && ~(isnumeric(v) || islogical(v) || ischar(v) || isstring(v)), continue; end
        rebuilt.(b.name) = v;
    end
    assert(isequal(rebuilt, context), 'the context rebuilt from the plan differs for "%s"', e);
end
A.Min = -inf;  A.Max = inf;  B.Min = -inf;
fprintf('PASS: 9 a context rebuilt from the plan is the resolver''s own\n');

% --- 10. what it costs --------------------------------------------------------
T.Expression = "A + B - " + string(modName) + ".Sel";
n = 300;
fresh = zeros(1, n);
for k = 1:n
    t = tic;
    [text, context] = hw.Parameter.resolveExpressionContext(char(T.Expression), 0, T, ...
        @() M.Parameters, @() M.Parameters, value);
    hw.Parameter.evalExpressionInContext(text, context, T.Name);
    fresh(k) = toc(t);
end
kept = zeros(1, n);
T.Value = 0;
for k = 1:n
    t = tic;
    T.Value = 0;
    kept(k) = toc(t);
end
fprintf('INFO: 10 resolve + evaluate, afresh: %.0f us; a whole assignment with the kept plan: %.0f us (medians of %d)\n', ...
    median(fresh) * 1e6, median(kept) * 1e6, n);

fprintf('smoke_test_expression_plan: ALL PASS\n');
end


function p = localAdd(M, name, value)
% add_parameter fills Values, not Value; a session assigns Value at dispatch.
p = M.add_parameter(name, value);
p.Value = value;
end


function v = localValue(p)
% As hw.Parameter.evaluateExpression_ reads a parameter for an expression.
if isequal(p.Access, 'Write')
    v = p.Values{1};
else
    v = p.Value;
end
end
