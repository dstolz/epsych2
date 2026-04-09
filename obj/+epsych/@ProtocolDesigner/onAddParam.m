function onAddParam(obj)
    module = obj.getSelectedTargetModule();
    if isempty(module)
        obj.LabelStatus.Text = 'No target module selected';
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

    parameterName = obj.getUniqueParameterName(module, requestedName);
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

    obj.refreshParameterTab();
    obj.LabelStatus.Text = sprintf('Added parameter %s. Edit the new row to customize it.', parameterName);
end

