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
    originalValues = parameter.Values;
    statusMessage = sprintf('Updated parameter %s', parameter.Name);
    nextStep = 'Review the updated row, then compile to refresh the preview.';
    try
        switch col
            case 3
                parameter.Type = char(evt.NewData);
                if isequal(parameter.Type, 'File')
                    originalFileLike = ~isempty(originalValues) && ...
                        any(cellfun(@(v) ischar(v) || (isstring(v) && isscalar(v)), originalValues));
                    if ~isequal(originalType, 'File') && ~originalFileLike
                        parameter.Values = {};
                    end
                    allowMultiple = obj.resolveFileSelectionMode(parameter);
                    parameter.isArray = allowMultiple;
                    [fileValue, cancelled, updatedAllowMultiple] = obj.editParameterFileValue(parameter, allowMultiple);
                    if cancelled
                        parameter.Type = originalType;
                        parameter.Values = originalValues;
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('File selection cancelled for %s', parameter.Name), ...
                            'Use Browse again when you are ready to choose files for this parameter.');
                        return
                    end
                    parameter.isArray = updatedAllowMultiple;
                    parameter.Values = hw.Parameter.normalizeValues(fileValue);
                    nextStep = 'Review the selected files, then compile to verify they produce the expected trials.';
                elseif isequal(parameter.Type, 'String')
                    originalStringLike = isempty(originalValues) || ...
                        all(cellfun(@(v) ischar(v) || isstring(v), originalValues));
                    if ~originalStringLike
                        parameter.Values = {};
                    end
                    [stringValue, cancelled, isArrayValue] = obj.editParameterStringValue(parameter);
                    if cancelled
                        parameter.Type = originalType;
                        parameter.Values = originalValues;
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('String edit cancelled for %s', parameter.Name), ...
                            'Use Edit Selected Value when you are ready to set one or more string values for this parameter.');
                        return
                    end
                    parameter.isArray = isArrayValue;
                    parameter.Values = hw.Parameter.normalizeValues(stringValue);
                    nextStep = 'Review the entered string values, then compile to verify the updated trials.';
                else
                    [coercedValue, isArrayValue] = obj.coerceValueForType(originalValues, parameter.Type);
                    parameter.Values = hw.Parameter.normalizeValues(coercedValue);
                    parameter.isArray = isArrayValue;
                    nextStep = 'Check Value, Min, and Max for the new type, then compile.';
                end
                if obj.sanitizeParameterTrigger(parameter)
                    statusMessage = sprintf('Cleared Trigger for %s because only Boolean parameters can be triggers', parameter.Name);
                    nextStep = 'Enable Trigger again only after setting the Type to Boolean.';
                end
                if obj.hasParameterExpression(parameter) && ~obj.parameterSupportsExpression(parameter)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s because type %s does not support expressions', parameter.Name, parameter.Type);
                    nextStep = 'Edit the Value column for this type, then compile again.';
                end
            case 4
                expressionText = strtrim(char(string(evt.NewData)));
                if isempty(expressionText)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s', parameter.Name);
                    nextStep = 'Enter a new expression or edit the Value column directly.';
                else
                    obj.setParameterExpression(parameter, expressionText);
                    obj.evaluateAndApplyParameterExpression(parameter, expressionText);
                    statusMessage = sprintf('%s = %s', expressionText, obj.getParameterValueDisplay(parameter));
                    nextStep = 'Confirm the computed value, then compile to check the updated trial set.';
                end
            case 5
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
            case 6
                if isequal(parameter.Type, 'String')
                    [stringValue, isArrayValue] = obj.parseStringParameterValue(evt.NewData);
                    parameter.isArray = isArrayValue;
                    parameter.Values = hw.Parameter.normalizeValues(stringValue);
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
                if ~obj.parameterAllowsTrigger(parameter)
                    parameter.isTrigger = false;
                    obj.refreshParameterTable();
                    obj.setStatus(sprintf('Trigger is only available for Boolean parameters like %s', parameter.Name), ...
                        'Set Type to Boolean first, then optionally enable Trigger.');
                    return
                end
                parameter.isTrigger = logical(evt.NewData);
            case 14
                parameter.Description = string(evt.NewData);
        end
    catch ME
        obj.refreshParameterTable();
        obj.setStatus(ME.message, 'Fix the edited cell value and try again.');
        return
    end

    obj.IsModified_ = true;
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

