function clearParameterExpression(~, parameter)
    if isstruct(parameter.UserData) && isfield(parameter.UserData, 'Expression')
        parameter.UserData = rmfield(parameter.UserData, 'Expression');
    end
end

