function aliases = getExpressionAliases(obj, parameter, parameters)
    if nargin < 3 || isempty(parameters)
        parameters = obj.getAllParameters();
    end

    aliases = {obj.getQualifiedExpressionAlias(parameter)};
    bareAlias = parameter.validName;
    aliasCount = sum(arrayfun(@(p) strcmp(p.validName, bareAlias), parameters));
    if aliasCount == 1
        aliases = [{bareAlias}, aliases];
    end
end

