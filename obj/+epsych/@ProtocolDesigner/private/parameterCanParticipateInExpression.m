function tf = parameterCanParticipateInExpression(~, parameter)
    if ~ismember(parameter.Type, {'Float', 'Integer', 'Boolean'})
        tf = false;
        return
    end
    value = parameter.Value;
    tf = (isnumeric(value) || islogical(value)) && ~isempty(value);
end

