function ensureParameterNameVisible(obj, parameterName, moduleName)
% ensureParameterNameVisible(obj, parameterName, moduleName)
% Clear the Find filter when it would hide the named parameter, so a row added
% while a search is active never appears to have vanished.
%
% Parameters:
%	parameterName	- Name of the parameter that must stay visible.
%	moduleName	- Name of the module owning the parameter.
    if isempty(obj.ParamNameFilter)
        return
    end

    if obj.matchesParameterNameFilter(parameterName, moduleName, obj.ParamNameFilter)
        return
    end

    obj.setParameterNameFilter('');
end
