function onBrowseSelectedFileParameter(obj)
    parameter = obj.getSelectedParameter();
    if isempty(parameter)
        obj.LabelStatus.Text = 'Select a parameter first';
        return
    end
    if ~isequal(parameter.Type, 'File')
        obj.LabelStatus.Text = sprintf('Parameter %s is not a File parameter', parameter.Name);
        return
    end

    allowMultiple = obj.resolveFileSelectionMode(parameter);
    [fileValue, cancelled, updatedAllowMultiple] = obj.editParameterFileValue(parameter, allowMultiple);
    if cancelled
        obj.LabelStatus.Text = sprintf('File selection cancelled for %s', parameter.Name);
        return
    end

    parameter.isArray = updatedAllowMultiple;
    parameter.Value = fileValue;
    obj.refreshParameterTable();
    obj.LabelStatus.Text = sprintf('Updated file value for %s', parameter.Name);
end

