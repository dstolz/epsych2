function tf = isLiteralConstantExpression(~, expressionText)
% tf = isLiteralConstantExpression(obj, expressionText)
% Return true when expression text is a pure numeric literal - "0", "-2.5",
% "[0 -5 -10]", "0:5:40", "2*pi" - rather than a rule that must be
% re-evaluated at dispatch.
%
% A literal can never produce a different result later, so storing it as a
% live Expression only forces hw.Parameter.set.Value to re-derive the same
% constant on every per-trial dispatch, overriding whatever the runtime
% assigned (e.g. a staircase-driven trial-table value) and pinning the
% parameter forever. Literals belong in Values; only text that references
% another parameter or calls a function stays an Expression.
%
% Parameters:
%	expressionText	- Expression text as entered by the user.
%
% Returns:
%	tf	- True when the text contains no identifiers beyond numeric
%		  constants (pi, Inf, NaN, true, false).

    expressionText = char(string(expressionText));

    % The lookbehind keeps the exponent of 1e3 / 2.5E-2 from reading as an
    % identifier, and skips property tails like the "Min" of Depth.Min (the
    % leading "Depth" still matches, correctly keeping that text an
    % expression).
    identifiers = regexp(expressionText, '(?<![\w.])[A-Za-z_]\w*', 'match');

    tf = all(ismember(identifiers, {'pi', 'Inf', 'inf', 'NaN', 'nan', 'true', 'false'}));
end
