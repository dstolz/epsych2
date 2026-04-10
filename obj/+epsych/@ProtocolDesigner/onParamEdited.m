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
    nextStep = 'Review the updated row, then compile to refresh the preview.';
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
                nextStep = 'Edit the parameter in its new module or add another parameter there.';
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
                        obj.setStatus(sprintf('File selection cancelled for %s', parameter.Name), ...
                            'Use Browse again when you are ready to choose files for this parameter.');
                        return
                    end
                    parameter.isArray = updatedAllowMultiple;
                    parameter.Value = fileValue;
                    nextStep = 'Review the selected files, then compile to verify they produce the expected trials.';
                elseif isequal(parameter.Type, 'String')
                    if ~(ischar(originalValue) || isstring(originalValue) || iscell(originalValue))
                        parameter.Value = '';
                    end
                    [stringValue, cancelled, isArrayValue] = obj.editParameterStringValue(parameter);
                    if cancelled
                        parameter.Type = originalType;
                        parameter.Value = originalValue;
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('String edit cancelled for %s', parameter.Name), ...
                            'Use Edit Selected Value when you are ready to set one or more string values for this parameter.');
                        return
                    end
                    parameter.isArray = isArrayValue;
                    parameter.Value = stringValue;
                    nextStep = 'Review the entered string values, then compile to verify the updated trials.';
                else
                    [coercedValue, isArrayValue] = obj.coerceValueForType(originalValue, parameter.Type);
                    parameter.Value = coercedValue;
                    parameter.isArray = isArrayValue;
                    nextStep = 'Check Value, Min, and Max for the new type, then compile.';
                end
                if obj.hasParameterExpression(parameter) && ~obj.parameterSupportsExpression(parameter)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s because type %s does not support expressions', parameter.Name, parameter.Type);
                    nextStep = 'Edit the Value column for this type, then compile again.';
                end
            case 5
                expressionText = strtrim(char(string(evt.NewData)));
                if isempty(expressionText)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s', parameter.Name);
                    nextStep = 'Enter a new expression or edit the Value column directly.';
                else
                    obj.setParameterExpression(parameter, expressionText);
                    obj.evaluateAndApplyParameterExpression(parameter, expressionText);
                    statusMessage = sprintf('%s = %s', expressionText, parameter.ValueStr);
                    nextStep = 'Confirm the computed value, then compile to check the updated trial set.';
                end
            case 6
                pairSelection = char(string(evt.NewData));
                if strcmp(pairSelection, '<Create Pair...>')
                    pairName = obj.promptForNewPairName();
                    if isempty(pairName)
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('Pair creation cancelled for %s', parameter.Name), ...
                            'Choose an existing pair or create a new pair name when you are ready.');
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
                    nextStep = 'Choose a pair again only if this parameter should stay linked to another one.';
                else
                    statusMessage = sprintf('Paired %s with group %s', parameter.Name, pairName);
                    nextStep = 'Assign the same pair group to the related parameter if needed.';
                end
            case 7
                if isequal(parameter.Type, 'String')
                    [stringValue, isArrayValue] = obj.parseStringParameterValue(evt.NewData);
                    parameter.isArray = isArrayValue;
                    parameter.Value = stringValue;
                    statusMessage = sprintf('Updated string value for %s', parameter.Name);
                    if isArrayValue
                        nextStep = 'Use semicolons in the Value cell to keep editing the string list, or open Edit Selected Value for a larger editor.';
                    else
                        nextStep = 'Edit the Value cell again or open Edit Selected Value to switch this parameter to a string array.';
                    end
                else
                    obj.refreshParameterTable();
                    obj.setStatus(sprintf('Value for %s is read-only', parameter.Name), ...
                        'Only String values support direct table edits. Use Expression or the type-specific editor instead.');
                    return
                end
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
        obj.setStatus(ME.message, 'Fix the edited cell value and try again.');
        return
    end

    obj.refreshExpressionValues();
    obj.refreshParameterTable();
    currentErrorMessage = obj.getExpressionErrorMessage(parameter);
    if ~isempty(currentErrorMessage)
        obj.setStatus(currentErrorMessage, ...
            'Fix the highlighted parameter values or expressions, then compile again.');
        return
    end

    obj.setStatus(statusMessage, nextStep);
end

