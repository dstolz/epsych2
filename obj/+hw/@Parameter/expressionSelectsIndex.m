function tf = expressionSelectsIndex(type)
% tf = hw.Parameter.expressionSelectsIndex(type)
% Report whether an Expression on a parameter of this Type selects one of the
% parameter's items by index instead of computing the value itself.
%
% 'String' and 'StimType' levels cannot be produced by arithmetic, so an
% expression on those types is interpreted as a 1-based index into the item
% list held in Values. Every other type uses the expression result directly.
%
% Parameters:
%   type - hw.Parameter Type name (char or string).
%
% Returns:
%   tf - True for the index-selecting types.
%
% See also: hw.Parameter.selectValueByIndex
tf = ismember(char(string(type)), {'String', 'StimType'});
end
