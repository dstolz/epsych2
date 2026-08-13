function tf = parameterCanParticipateInExpression(~, parameter)
% tf = parameterCanParticipateInExpression(~, parameter)
% Return true when a parameter type and value shape support expressions.
%
% Parameters:
%	parameter	- Parameter to test for expression compatibility.
%
% Returns:
%	tf	- True when the parameter can be referenced in expressions.
    if ~ismember(parameter.Type, {'Float', 'Integer', 'Boolean'})
        tf = false;
        return
    end
    % At design time, trial levels are in Values (cell array) while Value
    % may be empty. Accept the parameter if either Value or at least one
    % element of Values is numeric/logical.
    % Write-only parameters have no readable Value: get.Value logs a critical
    % message and returns NaN, so decide on Values alone for those.
    if ~isequal(parameter.Access, 'Write')
        value = parameter.Value;
        if (isnumeric(value) || islogical(value)) && ~isempty(value)
            tf = true;
            return
        end
    end
    tf = ~isempty(parameter.Values) && ...
        all(cellfun(@(v) isnumeric(v) || islogical(v), parameter.Values));
end

