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
            case 2
                destinationModule = obj.resolveParameterTargetModule(parameter, evt.NewData);
                sourceModule = parameter.Module;
                if ~isequal(destinationModule, sourceModule)
                    sourceKeepMask = sourceModule.Parameters ~= parameter;
                    sourceModule.Parameters = sourceModule.Parameters(sourceKeepMask);
                    destinationModule.Parameters(end + 1) = parameter;
                    parameter.Module = destinationModule;
                end
                statusMessage = sprintf('Assigned %s to %s', parameter.Name, destinationModule.Name);
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
                pairSelection = char(string(evt.NewData));
                if strcmp(pairSelection, '<Create Pair...>')
                    pairName = obj.promptForNewPairName();
                    if isempty(pairName)
                        obj.refreshParameterTable();
                        obj.LabelStatus.Text = sprintf('Pair creation cancelled for %s', parameter.Name);
                        return
                    end
                elseif strcmp(pairSelection, '<None>')
                    pairName = '';
                else
                    pairName = pairSelection;
                end

                obj.setParameterPair(parameter, pairName);
                pairName = obj.getParameterPair(parameter);
                if isempty(pairName)
                    statusMessage = sprintf('Cleared pair for %s', parameter.Name);
                else
                    statusMessage = sprintf('Paired %s with group %s', parameter.Name, pairName);
                end
            case 7
                obj.refreshParameterTable();
                obj.LabelStatus.Text = sprintf('Value for %s is read-only. Edit the Expression column instead.', parameter.Name);
                return
            case 8
                parameter.Min = double(evt.NewData);
            case 9
                parameter.Max = double(evt.NewData);
            case 10
                parameter.isRandom = logical(evt.NewData);
            case 11
                parameter.Access = char(evt.NewData);
            case 12
                parameter.Unit = char(evt.NewData);
            case 13
                parameter.Visible = logical(evt.NewData);
            case 14
                parameter.isTrigger = logical(evt.NewData);
            case 15
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

