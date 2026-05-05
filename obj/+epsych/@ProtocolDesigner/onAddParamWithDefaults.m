function onAddParamWithDefaults(obj, type, trigger)
% onAddParamWithDefaults(obj, type, trigger)
% Create a new parameter in the selected module with specified defaults.
    module = obj.getSelectedTargetModule();
    if isempty(module)
        obj.setStatus('No target module selected', ...
            'Choose a target interface and module before adding a parameter.');
        return
    end

    defaultName = obj.getUniqueParameterName(module, 'param');
    answer = obj.promptForParameterName(defaultName);
    if isempty(answer)
        return
    end

    requestedName = strtrim(answer{1});
    if isempty(requestedName)
        requestedName = defaultName;
    end

    try
        requestedName = obj.validateParameterName(requestedName);
        parameterName = obj.getUniqueParameterName(module, requestedName);
    catch ME
        obj.setStatus(ME.message, ...
            'Use a valid MATLAB identifier such as stimLevel or targetGain.');
        return
    end

    % Set defaults based on type
    switch lower(type)
        case 'boolean'
            paramType = 'Boolean';
            defaultValue = false;
            if trigger
                description = 'Trigger parameter';
            else
                description = '';
            end
        case 'float'
            paramType = 'Float';
            defaultValue = 1.0;
            description = '';
        case 'string'
            paramType = 'String';
            defaultValue = '';
            description = '';
        case 'integer'
            paramType = 'Integer';
            defaultValue = 1;
            description = '';
        otherwise
            paramType = 'Float';
            defaultValue = 1;
            description = '';
    end

    module.add_parameter(parameterName, defaultValue, ...
        Type = paramType, ...
        Access = 'Read / Write', ...
        Unit = '', ...
        isRandom = false, ...
        Visible = true, ...
        isArray = false, ...
        Min = -inf, ...
        Max = inf, ...
        Description = description);

    obj.IsModified_ = true;
    obj.refreshParameterTab();
    obj.setStatus(sprintf('Added parameter %s', parameterName), ...
        'Edit the new row to set type, value, and limits before compiling.');
end