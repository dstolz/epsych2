function onParamSelected(obj, evt)
    % Restore the truncated display for the Value cell if we are leaving it.
    prevRow = obj.SelectedParamRow;
    prevCol = obj.SelectedParamCol;
    obj.SelectedParamRow = 0;
    obj.SelectedParamCol = 0;

    if prevCol == 7 && prevRow >= 1 && prevRow <= numel(obj.ParameterHandles)
        obj.TableParams.Data{prevRow, 7} = obj.getParameterValueDisplay(obj.ParameterHandles{prevRow});
    end

    if isempty(evt.Indices)
        return
    end

    row = evt.Indices(1, 1);
    col = evt.Indices(1, 2);
    obj.SelectedParamRow = row;
    obj.SelectedParamCol = col;

    % Swap in full untruncated value when entering the Value column.
    if col == 7 && row >= 1 && row <= numel(obj.ParameterHandles)
        obj.TableParams.Data{row, 7} = obj.getParameterValueFull(obj.ParameterHandles{row});
    end

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
                'Use Edit Selected Value to replace the selection or compile to verify the input set.');
        end
    elseif isequal(parameter.Type, 'String')
        if parameter.isArray && numel(parameter.Values) > 1
            obj.setStatus(sprintf('%s: %d string value(s)', parameter.Name, numel(parameter.Values)), ...
                'Edit the Value cell with semicolon-delimited text, or use Edit Selected Value to add, remove, or reorder entries.');
        else
            obj.setStatus(sprintf('Selected String parameter %s', parameter.Name), ...
                'Edit the Value cell directly, using semicolons for arrays, or use Edit Selected Value for a larger editor.');
        end
    elseif obj.hasParameterExpression(parameter)
        obj.setStatus(sprintf('%s = %s', obj.getParameterExpression(parameter), obj.getParameterValueDisplay(parameter)), ...
            'Edit the Expression cell if needed, then compile to refresh the preview.');
    else
        obj.setStatus(sprintf('Selected %s on %s', parameter.Name, parameter.Module.Name), ...
            'Edit the selected row or add another parameter to this module.');
    end
end

