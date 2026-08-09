function [spec, moduleOptions] = getModuleEditState(obj, iface, moduleIndex)
    if moduleIndex < 1 || moduleIndex > length(iface.Module)
        error('Selected module index %d is out of range.', moduleIndex);
    end

    [spec, interfaceOptions] = obj.getInterfaceEditState(iface);
    moduleFields = spec.options(arrayfun(@(field) strcmpi(char(string(field.scope)), 'module'), spec.options));
    if isempty(moduleFields)
        error('No module-scoped options are available for interface type %s.', char(iface.Type));
    end

    moduleOptions = struct();
    for idx = 1:numel(moduleFields)
        field = moduleFields(idx);
        if isfield(interfaceOptions, field.name)
            moduleOptions.(field.name) = localSelectModuleScopedValue_(interfaceOptions.(field.name), moduleIndex, field.defaultValue);
        else
            moduleOptions.(field.name) = field.defaultValue;
        end
    end
end

function value = localSelectModuleScopedValue_(rawValue, moduleIndex, fallbackValue)
    if isempty(rawValue)
        value = fallbackValue;
        return
    end

    if iscell(rawValue)
        if moduleIndex <= numel(rawValue) && ~isempty(rawValue{moduleIndex})
            value = rawValue{moduleIndex};
        else
            value = fallbackValue;
        end
        return
    end

    if isnumeric(rawValue) || islogical(rawValue)
        if moduleIndex <= numel(rawValue)
            value = rawValue(moduleIndex);
        else
            value = fallbackValue;
        end
        return
    end

    if isstring(rawValue)
        if moduleIndex <= numel(rawValue)
            value = rawValue(moduleIndex);
        else
            value = fallbackValue;
        end
        return
    end

    value = rawValue;
end