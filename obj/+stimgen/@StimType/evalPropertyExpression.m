function value = evalPropertyExpression(obj, propName, expressionText)
% value = evalPropertyExpression(obj, propName, expressionText)
% Evaluate a guarded MATLAB expression for a vectorizable numeric property.
% Accepts range syntax (0:10:50), vector literals ([1 2 3]), general
% MATLAB expressions, and cross-property references using bare property
% names or qualified ClassName.PropertyName notation.
%
% Parameters:
%   propName       - Name of the target property.
%   expressionText - MATLAB expression string to evaluate.
%
% Returns:
%   value - Resulting double scalar or vector.
value = obj.evaluate_property_expression_(propName, char(string(expressionText)));
