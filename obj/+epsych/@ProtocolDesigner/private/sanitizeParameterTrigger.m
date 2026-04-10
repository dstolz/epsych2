function changed = sanitizeParameterTrigger(obj, parameter)
    changed = false;
    if obj.parameterAllowsTrigger(parameter)
        return
    end

    if parameter.isTrigger
        parameter.isTrigger = false;
        changed = true;
    end
end