function tf = parameterSupportsExpression(~, parameter)
    tf = ismember(parameter.Type, {'Float', 'Integer', 'Boolean'}) && ~parameter.isTrigger;
end

