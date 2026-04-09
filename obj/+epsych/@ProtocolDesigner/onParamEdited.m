function onParamEdited(obj, evt)
    % onParamEdited(obj, evt)
    % Apply an in-table parameter edit to the underlying model.
    % Handles type changes, expression updates, file-value editing, and
    % per-column property updates before refreshing dependent UI state.
    %
    % Parameters:
    % 	evt	- Table edit event with row, column, and new cell value.
    row = evt.Indices(1);
    col = evt.Indices(2);

    if row < 1 || row > numel(obj.ParameterHandles)
        return
    end

    parameter = obj.ParameterHandles{row};
    originalType = parameter.Type;
    originalValue = parameter.Value;
    statusMessage = sprintf('Updated parameter %s', parameter.Name);
    try
        switch col
            case 4
                parameter.Type = char(evt.NewData);
                if isequal(parameter.Type, 'File')
                    if ~isequal(originalType, 'File') && ~obj.isFileLikeValue(originalValue)
                        parameter.Value = '';
                    end
                    allowMultiple = obj.resolveFileSelectionMode(parameter);
                    parameter.isArray = allowMultiple;
                    [fileValue, cancelled, updatedAllowMultiple] = obj.editParameterFileValue(parameter, allowMultiple);
                    if cancelled
                        parameter.Type = originalType;
                        parameter.Value = originalValue;
                        obj.refreshParameterTable();
                        obj.LabelStatus.Text = sprintf('File selection cancelled for %s', parameter.Name);
                        return
                    end
                    parameter.isArray = updatedAllowMultiple;
                    parameter.Value = fileValue;
                else
                    [coercedValue, isArrayValue] = obj.coerceValueForType(originalValue, parameter.Type);
                    parameter.Value = coercedValue;
                    parameter.isArray = isArrayValue;
                end
                if obj.hasParameterExpression(parameter) && ~obj.parameterSupportsExpression(parameter)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s because type %s does not support expressions', parameter.Name, parameter.Type);
                end
            case 5
                expressionText = strtrim(char(string(evt.NewData)));
                if isempty(expressionText)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s', parameter.Name);
                else
                    obj.setParameterExpression(parameter, expressionText);
                    obj.evaluateAndApplyParameterExpression(parameter, expressionText);
                    statusMessage = sprintf('%s = %s', expressionText, parameter.ValueStr);
                end
            case 6
                if obj.hasParameterExpression(parameter)
                    obj.refreshParameterTable();
                    obj.LabelStatus.Text = sprintf('Parameter %s is expression-controlled. Edit the Expression column instead.', parameter.Name);
                    return
                end
                if isequal(parameter.Type, 'File')
                    [fileValue, cancelled, updatedAllowMultiple] = obj.editParameterFileValue(parameter, parameter.isArray);
                    if cancelled
                        obj.refreshParameterTable();
                        obj.LabelStatus.Text = sprintf('File selection cancelled for %s', parameter.Name);
                        return
                    end
                    parameter.isArray = updatedAllowMultiple;
                    parameter.Value = fileValue;
                else
                    parameter.Value = obj.parseValue(evt.NewData);
                end
            case 7
                parameter.Min = double(evt.NewData);
            case 8
                parameter.Max = double(evt.NewData);
            case 9
                parameter.isRandom = logical(evt.NewData);
            case 10
                parameter.Access = char(evt.NewData);
            case 11
                parameter.Unit = char(evt.NewData);
            case 12
                parameter.Visible = logical(evt.NewData);
            case 13
                parameter.isTrigger = logical(evt.NewData);
            case 14
                parameter.Description = string(evt.NewData);
        end
    catch ME
        obj.refreshParameterTable();
        obj.LabelStatus.Text = ME.message;
        return
    end

    obj.refreshExpressionValues();
    obj.refreshParameterTable();
    obj.LabelStatus.Text = statusMessage;
end

