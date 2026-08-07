function result = evalExpressionInContext(rewrittenText, context, targetName)
% result = hw.Parameter.evalExpressionInContext(rewrittenText, context, targetName)
% Evaluate a rewritten Expression with the given context variables.
%
% Companion to hw.Parameter.resolveExpressionContext: loads every context
% field into the local workspace and evaluates the single-statement
% expression. Kept in its own function so the eval workspace contains only
% the context variables (plus this function's few locals) regardless of
% caller.
%
% Parameters:
%   rewrittenText - char, expression with references already rewritten to
%                   context aliases.
%   context       - struct of variables to expose to the expression. Must
%                   include field Value (the incoming value).
%   targetName    - Parameter name used in the error message.
%
% Returns:
%   result - The expression's result.

% Load context variables into local workspace
names = fieldnames(context);
for idx = 1:numel(names)
    eval([names{idx} ' = context.(names{idx});']);
end

% Evaluate; expression is a single statement that produces a result
Value = context.Value;
try
    exprResult__ = eval(rewrittenText);
catch ME
    error('hw:Parameter:ExpressionError', ...
        'Expression evaluation failed for parameter "%s": %s', targetName, ME.message);
end

result = exprResult__;
