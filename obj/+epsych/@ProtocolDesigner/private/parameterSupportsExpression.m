function tf = parameterSupportsExpression(~, parameter)
% tf = parameterSupportsExpression(~, parameter)
% Return true when the Expression column applies to this parameter.
%
% Float, Integer, and Boolean expressions compute the value itself. String and
% StimType expressions instead select one of the parameter's items by 1-based
% index (hw.Parameter.expressionSelectsIndex). Triggers fire rather than carry
% a value, so they never take an expression.
%
% Parameters:
%	parameter	- Parameter to test.
%
% Returns:
%	tf	- True when an expression can be stored on this parameter.
    tf = ismember(parameter.Type, {'Float', 'Integer', 'Boolean', 'String', 'StimType'}) ...
        && ~parameter.isTrigger;
end
