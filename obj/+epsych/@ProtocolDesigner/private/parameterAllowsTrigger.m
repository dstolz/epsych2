function tf = parameterAllowsTrigger(~, parameter)
    tf = strcmp(char(string(parameter.Type)), 'Boolean');
end