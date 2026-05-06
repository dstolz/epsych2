function value = evaluate_property_expression_(obj, propName, expressionText)
% value = evaluate_property_expression_(obj, propName, expressionText)
% Evaluate a guarded MATLAB expression for a numeric property.
% Supports vector/range literals, MATLAB expressions, and references
% to other properties by bare name or ClassName.PropertyName form.
%
% Parameters:
%   propName       - Name of the target property being set.
%   expressionText - MATLAB expression string entered by the user.
%
% Returns:
%   value - Evaluated double vector or scalar.

expressionText = strtrim(expressionText);
if isempty(expressionText)
    error('Expression cannot be empty.');
end
if ~isempty(regexp(expressionText, '(?<![<>=~])=(?!=)', 'once'))
    error('Assignments are not allowed in expressions.');
end
if contains(expressionText, ';')
    error('Only a single expression is allowed.');
end
expressionText = obj.rewrite_qualified_property_refs_(expressionText);
expressionText = strip(expressionText, 'both', '"');
expressionText = strip(expressionText, 'both', '''');
context = obj.build_expression_context_(propName);
names = fieldnames(context);
for k_ = 1:numel(names)
    eval(sprintf('%s = context.(names{%d});', names{k_}, k_));
end
value = eval(expressionText);
if ischar(value) || (isstring(value) && isscalar(value))
    nestedExpression = strtrim(char(string(value)));
    if strcmp(nestedExpression, expressionText)
        error('Expression for %s must evaluate to a numeric or logical value.', propName);
    end
    value = eval(nestedExpression);
end
if ~(isnumeric(value) || islogical(value)) || isempty(value)
    error('Expression for %s must evaluate to a numeric or logical value.', propName);
end
if ~all(isfinite(value(:)))
    error('Expression for %s must evaluate to finite numeric values.', propName);
end
value = double(value);
