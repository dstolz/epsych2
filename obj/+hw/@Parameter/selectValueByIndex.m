function [item, index] = selectValueByIndex(result, values, paramName)
% [item, index] = hw.Parameter.selectValueByIndex(result, values, paramName)
% Resolve an index-valued expression result against a parameter's item list.
%
% Used for 'String' and 'StimType' parameters, where an Expression chooses
% which of the parameter's items to use rather than computing the value. The
% result must be a single whole number between 1 and numel(values); MATLAB
% arithmetic readily produces fractions, so the errors below name round() and
% fix() as the fix rather than leaving the caller to guess.
%
% Parameters:
%   result    - Raw expression result to interpret as a 1-based index.
%   values    - The parameter's item list (hw.Parameter.Values).
%   paramName - Parameter name used in error messages.
%
% Returns:
%   item  - The selected element of values.
%   index - The validated 1-based index.
%
% See also: hw.Parameter.expressionSelectsIndex
arguments
    result
    values (1,:) cell
    paramName (1,:) char = 'this parameter'
end

nItems = numel(values);
if nItems == 0
    error('hw:Parameter:IndexExpressionNoItems', ...
        ['Expression for "%s" selects an item by index, but the parameter has no items. ' ...
        'Add the items to the Value column first.'], paramName);
end

if ~(isnumeric(result) || islogical(result)) || ~isscalar(result)
    error('hw:Parameter:IndexExpressionNotScalar', ...
        ['Expression for "%s" must evaluate to a single number that indexes its %d item(s), not %s. ' ...
        'The expression chooses which item to use.'], ...
        paramName, nItems, localDescribeResult_(result));
end

index = double(result);
if ~isfinite(index) || index ~= floor(index)
    error('hw:Parameter:IndexExpressionNotInteger', ...
        ['Expression for "%s" must evaluate to a whole-number index into its %d item(s), but produced %s. ' ...
        'Wrap the calculation in round(), fix(), floor(), or ceil().'], ...
        paramName, nItems, localFormatNumber_(index));
end

if index < 1 || index > nItems
    error('hw:Parameter:IndexExpressionOutOfRange', ...
        ['Expression for "%s" produced index %d, which is outside the range 1 to %d of its item list. ' ...
        'Keep the result in range, for example min(max(round(x), 1), %d).'], ...
        paramName, index, nItems, nItems);
end

item = values{index};
end


function txt = localDescribeResult_(result)
if isnumeric(result) || islogical(result)
    txt = sprintf('a %s array with %d elements', class(result), numel(result));
else
    txt = sprintf('a %s value', class(result));
end
end


function txt = localFormatNumber_(value)
if isnan(value)
    txt = 'NaN';
elseif isinf(value)
    txt = 'Inf';
else
    txt = num2str(value, '%g');
end
end
