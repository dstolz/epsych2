function tf = parameterCanParticipateInExpression(~, parameter)
    if ~ismember(parameter.Type, {'Float', 'Integer', 'Boolean'})
        tf = false;
        return
    end
    % At design time, trial levels are in Values (cell array) while Value
    % may be empty. Accept the parameter if either Value or at least one
    % element of Values is numeric/logical.
    value = parameter.Value;
    if (isnumeric(value) || islogical(value)) && ~isempty(value)
        tf = true;
        return
    end
    tf = ~isempty(parameter.Values) && ...
        all(cellfun(@(v) isnumeric(v) || islogical(v), parameter.Values));
end

