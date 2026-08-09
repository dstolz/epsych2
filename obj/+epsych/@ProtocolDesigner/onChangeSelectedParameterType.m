function onChangeSelectedParameterType(obj, typeName)
% onChangeSelectedParameterType(obj, typeName)
% Change the currently selected parameter to a new type using a keyboard shortcut.
    row = obj.SelectedParamRow;
    if row < 1 || row > numel(obj.ParameterHandles)
        obj.setStatus('No parameter selected', ...
            'Select a parameter row and press Ctrl+1..9 to change its type.');
        return
    end

    if ~ismember(typeName, obj.getTypeOptions())
        obj.setStatus(sprintf('Unsupported parameter type: %s', typeName), ...
            'Use a valid parameter type shortcut instead.');
        return
    end

    evt = struct('Indices', [row, 3], 'NewData', typeName);
    obj.onParamEdited(evt);
end