function tf = parameterSupportsExpression(~, parameter)
    tf = ismember(parameter.Type, {'Float', 'Integer', 'Boolean'}) && ~parameter.isTrigger && ~isequal(parameter.Type, 'StimType');
end

