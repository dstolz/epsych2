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
                elseif isequal(parameter.Type, 'StimType')
                    originalStimTypeLike = ~isempty(originalValues) && ...
                        all(cellfun(@(v) isa(v, 'stimgen.StimType'), originalValues));
                    if ~originalStimTypeLike
                        parameter.Values = {};
                    end
                    [stimValues, cancelled] = obj.editParameterStimTypeValue(parameter);
                    if cancelled
                        parameter.Type = originalType;
                        parameter.Values = originalValues;
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('StimType selection cancelled for %s', parameter.Name), ...
                            'Use the Value column to assign StimType levels when ready.');
                        return
                    end
                    parameter.isArray = numel(stimValues) > 1;
                    parameter.Values = hw.Parameter.normalizeValues(stimValues);
                    nextStep = 'Review the assigned stimulus types, then compile to verify the updated trials.';
                elseif isequal(parameter.Type, 'Coefficient Buffer')
                    [coefValue, cancelled] = obj.editParameterCoefficientBufferValue(parameter);
                    if cancelled
                        parameter.Type = originalType;
                        parameter.Values = originalValues;
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('Coefficient buffer edit cancelled for %s', parameter.Name), ...
                            'Use the Value column to paste coefficients or extract them from a calibration file.');
                        return
                    end
                    if isempty(coefValue)
                        parameter.Values = {};
                        parameter.isArray = false;
                    else
                        parameter.Values = {coefValue};
                        parameter.isArray = numel(coefValue) > 1;
                    end
                    nextStep = 'Review the coefficient buffer, then compile to verify the updated trials.';
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
                    
                    % Auto-set Boolean limits to [0, 1]
                    if isequal(parameter.Type, 'Boolean')
                        parameter.Min = 0;
                        parameter.Max = 1;
                        nextStep = 'Boolean limits are now [0, 1]. Review value and compile.';
                    else
                        nextStep = 'Check Value, Min, and Max for the new type, then compile.';
                    end
                end
                if obj.sanitizeParameterTrigger(parameter)
                    statusMessage = sprintf('Cleared Trigger for %s because only Boolean parameters can be triggers', parameter.Name);
                    nextStep = 'Enable Trigger again only after setting the Type to Boolean.';
                end
                if obj.hasParameterExpression(parameter) && ~obj.parameterSupportsExpression(parameter)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s because type %s does not support expressions', parameter.Name, parameter.Type);
                    nextStep = 'Edit the Value column for this type, then compile again.';
                elseif obj.hasParameterExpression(parameter) && ...
                        hw.Parameter.expressionSelectsIndex(parameter.Type) ~= hw.Parameter.expressionSelectsIndex(originalType)
                    % The stored text survives the type change but its meaning flips
                    % between "the value" and "which item to use".
                    if hw.Parameter.expressionSelectsIndex(parameter.Type)
                        statusMessage = sprintf('Expression for %s now chooses which item to use, because %s parameters index into their Value list', ...
                            parameter.Name, parameter.Type);
                        nextStep = sprintf('Make the expression return a whole number from 1 to %d, using round() or fix() if it can be fractional.', ...
                            max(numel(parameter.Values), 1));
                    else
                        statusMessage = sprintf('Expression for %s now computes the value directly, because %s parameters do not index a list', ...
                            parameter.Name, parameter.Type);
                        nextStep = 'Confirm the computed value, then compile again.';
                    end
                end
            case 4
                expressionText = strtrim(char(string(evt.NewData)));
                if isempty(expressionText)
                    obj.clearParameterExpression(parameter);
                    statusMessage = sprintf('Cleared expression for %s', parameter.Name);
                    nextStep = 'Enter a new expression or edit the Value column directly.';
                else
                    obj.setParameterExpression(parameter, expressionText);
                    appliedText = obj.evaluateAndApplyParameterExpression(parameter, expressionText);
                    if ~obj.hasParameterExpression(parameter)
                        % A constant or explicit level list was stored as fixed
                        % Values and the expression dropped: only text that must
                        % be re-evaluated each trial stays an Expression.
                        statusMessage = sprintf('%s = %s (stored as a fixed value, not a live expression)', ...
                            parameter.Name, appliedText);
                        nextStep = 'Fixed values stay editable at runtime; reference another parameter here if the value should be computed each trial instead.';
                    else
                        statusMessage = sprintf('%s = %s', expressionText, appliedText);
                        if hw.Parameter.expressionSelectsIndex(parameter.Type)
                            nextStep = sprintf('This expression chooses which item to use: it must return a whole number from 1 to %d each trial (round() or fix() if it can be fractional).', ...
                                numel(parameter.Values));
                        else
                            nextStep = 'Confirm the computed value, then compile to check the updated trial set.';
                        end
                    end
                end
            case 9
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
            case 5
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
                elseif isequal(parameter.Type, 'StimType')
                    [stimValues, cancelled] = obj.editParameterStimTypeValue(parameter);
                    if cancelled
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('StimType edit cancelled for %s', parameter.Name), ...
                            'Double-click the Value cell again to assign StimType levels.');
                        return
                    end
                    parameter.isArray = numel(stimValues) > 1;
                    parameter.Values = hw.Parameter.normalizeValues(stimValues);
                    statusMessage = sprintf('Updated StimType values for %s', parameter.Name);
                    nextStep = 'Review the assigned stimulus types, then compile.';
                elseif isequal(parameter.Type, 'Coefficient Buffer')
                    [coefValue, cancelled] = obj.editParameterCoefficientBufferValue(parameter);
                    if cancelled
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('Coefficient buffer edit cancelled for %s', parameter.Name), ...
                            'Edit the Value cell again to paste coefficients or extract them from a calibration file.');
                        return
                    end
                    if isempty(coefValue)
                        parameter.Values = {};
                        parameter.isArray = false;
                        statusMessage = sprintf('Cleared coefficient buffer for %s', parameter.Name);
                    else
                        parameter.Values = {coefValue};
                        parameter.isArray = numel(coefValue) > 1;
                        statusMessage = sprintf('Updated coefficient buffer for %s (%d coefficients)', ...
                            parameter.Name, numel(coefValue));
                    end
                    nextStep = 'Review the coefficient buffer, then compile.';
                elseif ismember(parameter.Type, {'Float', 'Integer', 'Boolean'}) && ~parameter.isTrigger
                    % Direct numeric entry: evaluate once, store the result as
                    % fixed design-time Values. Any prior Expression is removed -
                    % typing into the Value column declares the value, not a
                    % rule, as this parameter's source of truth.
                    valueText = strtrim(char(string(evt.NewData)));
                    if isempty(valueText)
                        obj.refreshParameterTable();
                        obj.setStatus(sprintf('Value for %s was not changed', parameter.Name), ...
                            'Enter a number, or a level list like [0 -5 -10] or 0:5:40, in the Value cell.');
                        return
                    end
                    result = obj.evaluateParameterExpression(parameter, valueText);
                    result = obj.normalizeExpressionResult(parameter, result);
                    hadExpression = obj.hasParameterExpression(parameter);
                    priorExpression = obj.getParameterExpression(parameter);
                    parameter.Values = hw.Parameter.normalizeValues(result);
                    parameter.isArray = numel(result) > 1;
                    obj.clearParameterExpression(parameter);
                    if hadExpression
                        statusMessage = sprintf('Set %s to a fixed value and removed its expression "%s"', ...
                            parameter.Name, priorExpression);
                        nextStep = 'Re-enter the expression in the Expression column if this parameter should stay computed each trial.';
                    else
                        statusMessage = sprintf('Updated value for %s', parameter.Name);
                        nextStep = 'Compile to check the updated trial set.';
                    end
                else
                    obj.refreshParameterTable();
                    obj.setStatus(sprintf('Value for %s is read-only', parameter.Name), ...
                        'Use the Type column''s editor (or Edit Selected Value) for File parameters and triggers.');
                    return
                end
            case 6
                parameter.Min = double(evt.NewData);
            case 7
                parameter.Max = double(evt.NewData);
            case 8
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
                parameter.UpdateEveryTrial = logical(evt.NewData);
            case 15
                parameter.Description = string(evt.NewData);
        end
    catch ME
        obj.refreshParameterTable();
        obj.setStatus(ME.message, 'Fix the edited cell value and try again.');
        return
    end

    % Editing the item list of an index-selecting parameter can move the
    % expression's target or push it out of range, so say what the range is now.
    if col == 5 && obj.hasParameterExpression(parameter) && hw.Parameter.expressionSelectsIndex(parameter.Type)
        nextStep = sprintf('The expression for %s picks one of these items by index, so keep its result between 1 and %d.', ...
            parameter.Name, numel(parameter.Values));
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

