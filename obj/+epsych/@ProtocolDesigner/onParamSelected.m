function onParamSelected(obj, evt)
    obj.SelectedParamRow = 0;
    if isempty(evt.Indices)
        return
    end

    obj.SelectedParamRow = evt.Indices(1, 1);
    parameter = obj.ParameterHandles{obj.SelectedParamRow};
    expressionErrorMessage = obj.getExpressionErrorMessage(parameter);
    if ~isempty(expressionErrorMessage)
        obj.LabelStatus.Text = expressionErrorMessage;
    elseif isequal(parameter.Type, 'File')
        fileList = obj.getParameterFileList(parameter);
        if isempty(fileList)
            obj.LabelStatus.Text = sprintf('Selected file parameter %s (no files selected)', parameter.Name);
        else
            obj.LabelStatus.Text = sprintf('%s: %d file(s) selected', parameter.Name, numel(fileList));
        end
    elseif obj.hasParameterExpression(parameter)
        obj.LabelStatus.Text = sprintf('%s = %s', obj.getParameterExpression(parameter), parameter.ValueStr);
    end
end

