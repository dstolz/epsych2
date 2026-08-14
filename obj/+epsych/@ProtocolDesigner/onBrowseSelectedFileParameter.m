function onBrowseSelectedFileParameter(obj)
% onBrowseSelectedFileParameter(obj)
% Edit values for the selected File or String parameter.
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

    if isequal(parameter.Type, 'StimType')
        [stimValues, cancelled] = obj.editParameterStimTypeValue(parameter);
        if cancelled
            obj.setStatus(sprintf('StimType edit cancelled for %s', parameter.Name), ...
                'Use Edit Selected Value again when you are ready to update this StimType parameter.');
            return
        end
        parameter.isArray = numel(stimValues) > 1;
        parameter.Values = hw.Parameter.normalizeValues(stimValues);
        obj.refreshParameterTable();
        obj.setStatus(sprintf('Updated StimType levels for %s', parameter.Name), ...
            'Compile to verify the updated trial set.');
        return
    end

    if isequal(parameter.Type, 'Coefficient Buffer')
        [coefValue, cancelled] = obj.editParameterCoefficientBufferValue(parameter);
        if cancelled
            obj.setStatus(sprintf('Coefficient buffer edit cancelled for %s', parameter.Name), ...
                'Use Edit Selected Value again when you are ready to paste coefficients or extract them from a calibration file.');
            return
        end

        if isempty(coefValue)
            parameter.Values = {};
            parameter.isArray = false;
            obj.refreshParameterTable();
            obj.setStatus(sprintf('Cleared coefficient buffer for %s', parameter.Name), ...
                'Compile to confirm the cleared buffer produces the expected trial preview.');
        else
            parameter.Values = {coefValue};
            parameter.isArray = numel(coefValue) > 1;
            obj.refreshParameterTable();
            obj.setStatus(sprintf('Updated coefficient buffer for %s (%d coefficients)', ...
                parameter.Name, numel(coefValue)), ...
                'Compile to confirm the updated buffer produces the expected trial preview.');
        end
        return
    end

    obj.setStatus(sprintf('Parameter %s is not a File, String, StimType, or Coefficient Buffer parameter', parameter.Name), ...
        'This dialog supports File, String, StimType, and Coefficient Buffer parameters only.');
end

