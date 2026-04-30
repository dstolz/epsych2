function onAddParam(obj)
% onAddParam(obj)
% Create a new parameter in the selected module using default metadata.
    module = obj.getSelectedTargetModule();
    if isempty(module)
        obj.setStatus('No target module selected', ...
            'Choose a target interface and module before adding a parameter.');
        return
    end

    defaultName = obj.getUniqueParameterName(module, 'param');
    answer = inputdlg({'Parameter Name'}, 'Add Parameter', 1, {defaultName});
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

    module.add_parameter(parameterName, 1, ...
        Type = 'Float', ...
        Access = 'Read / Write', ...
        Unit = '', ...
        isRandom = false, ...
        Visible = true, ...
        isArray = false, ...
        Min = -inf, ...
        Max = inf, ...
        Description = "");

    obj.IsModified_ = true;
    obj.refreshParameterTab();
    obj.setStatus(sprintf('Added parameter %s', parameterName), ...
        'Edit the new row to set type, value, and limits before compiling.');
end

