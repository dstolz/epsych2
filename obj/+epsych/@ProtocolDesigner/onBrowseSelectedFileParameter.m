function onBrowseSelectedFileParameter(obj)
    parameter = obj.getSelectedParameter();
    if isempty(parameter)
        obj.setStatus('No parameter selected', 'Select a parameter row before browsing for files.');
        return
    end
    if ~isequal(parameter.Type, 'File')
        obj.setStatus(sprintf('Parameter %s is not a File parameter', parameter.Name), ...
            'Change its Type to File first if this parameter should point to files.');
        return
    end

    allowMultiple = obj.resolveFileSelectionMode(parameter);
    [fileValue, cancelled, updatedAllowMultiple] = obj.editParameterFileValue(parameter, allowMultiple);
    if cancelled
        obj.setStatus(sprintf('File selection cancelled for %s', parameter.Name), ...
            'Use Browse again when you are ready to choose files for this parameter.');
        return
    end

    parameter.isArray = updatedAllowMultiple;
    parameter.Value = fileValue;
    obj.refreshParameterTable();
    obj.setStatus(sprintf('Updated file value for %s', parameter.Name), ...
        'Compile to confirm the selected files produce the expected trial preview.');
end

