function onParamSelected(obj, evt)
    obj.SelectedParamRow = 0;
    if isempty(evt.Indices)
        return
    end

    obj.SelectedParamRow = evt.Indices(1, 1);
    parameter = obj.ParameterHandles{obj.SelectedParamRow};
    expressionErrorMessage = obj.getExpressionErrorMessage(parameter);
    if ~isempty(expressionErrorMessage)
        obj.setStatus(expressionErrorMessage, 'Fix the highlighted parameter values or expressions, then compile again.');
    elseif isequal(parameter.Type, 'File')
        fileList = obj.getParameterFileList(parameter);
        if isempty(fileList)
            obj.setStatus(sprintf('Selected file parameter %s (no files selected)', parameter.Name), ...
                'Use Browse or edit the Value cell to choose one or more files.');
        else
            obj.setStatus(sprintf('%s: %d file(s) selected', parameter.Name, numel(fileList)), ...
                'Use Browse to replace the selection or compile to verify the input set.');
        end
    elseif obj.hasParameterExpression(parameter)
        obj.setStatus(sprintf('%s = %s', obj.getParameterExpression(parameter), parameter.ValueStr), ...
            'Edit the Expression cell if needed, then compile to refresh the preview.');
    else
        obj.setStatus(sprintf('Selected %s on %s', parameter.Name, parameter.Module.Name), ...
            'Edit the selected row or add another parameter to this module.');
    end
end

