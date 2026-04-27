function onBrowseSelectedFileParameter(obj)
    parameter = obj.getSelectedParameter();
    if isempty(parameter)
        obj.setStatus('No parameter selected', 'Select a File or String parameter row before editing its value.');
        return
    end

    if isequal(parameter.Type, 'File')
        allowMultiple = obj.resolveFileSelectionMode(parameter);
        [fileValue, cancelled, updatedAllowMultiple] = obj.editParameterFileValue(parameter, allowMultiple);
        if cancelled
            obj.setStatus(sprintf('File selection cancelled for %s', parameter.Name), ...
                'Use Edit Selected Value again when you are ready to choose files for this parameter.');
            return
        end

        parameter.isArray = updatedAllowMultiple;
        parameter.Values = hw.Parameter.normalizeValues(fileValue);
        obj.refreshParameterTable();
        obj.setStatus(sprintf('Updated file value for %s', parameter.Name), ...
            'Compile to confirm the selected files produce the expected trial preview.');
        return
    end

    if isequal(parameter.Type, 'String')
        [stringValue, cancelled, isArrayValue] = obj.editParameterStringValue(parameter);
        if cancelled
            obj.setStatus(sprintf('String edit cancelled for %s', parameter.Name), ...
                'Use Edit Selected Value again when you are ready to update this String parameter.');
            return
        end

        parameter.isArray = isArrayValue;
        parameter.Values = hw.Parameter.normalizeValues(stringValue);
        obj.refreshParameterTable();
        obj.setStatus(sprintf('Updated string value for %s', parameter.Name), ...
            'Compile to confirm the updated String values produce the expected trial preview.');
        return
    end

    obj.setStatus(sprintf('Parameter %s is not a File or String parameter', parameter.Name), ...
        'This dialog currently supports File and String parameters only.');
end

