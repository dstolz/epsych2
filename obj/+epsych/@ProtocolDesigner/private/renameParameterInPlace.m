function renameParameterInPlace(obj, parameter, module, newName)
% renameParameterInPlace(obj, parameter, module, newName)
% Rename a parameter and repoint every expression that referenced it.
%
% Parameters:
%	parameter	- Parameter to rename.
%	module		- Module that owns the parameter.
%	newName		- New parameter name; must be unique within the module.
    newName = obj.validateParameterName(newName);
    oldName = parameter.Name;
    if strcmp(oldName, newName)
        return
    end

    isCollision = arrayfun(@(p) ~isequal(p, parameter) && strcmp(p.Name, newName), module.Parameters);
    if any(isCollision)
        error('Module %s already has a parameter named %s.', module.Name, newName);
    end

    parameter.Name = newName;
    obj.rewriteExpressionReferences(module, oldName, newName);
end
