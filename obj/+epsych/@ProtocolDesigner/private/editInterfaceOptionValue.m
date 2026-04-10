function [rawValue, cancelled] = editInterfaceOptionValue(obj, field, currentValue)
    dialogHeight = 236;
    controlHeight = 28;
    if strcmp(field.controlType, 'textarea') || strcmp(field.controlType, 'multiselect') || field.isList
        dialogHeight = 290;
        controlHeight = 56;
    end

    dialog = uifigure( ...
        'Name', sprintf('Edit %s', field.label), ...
        'Position', [320 220 620 dialogHeight], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off');

    uilabel(dialog, ...
        'Text', field.label, ...
        'Position', [20 dialogHeight - 42 220 22], ...
        'FontWeight', 'bold');

    guidance = field.description;
    extraGuidance = obj.describeInterfaceField(field);
    if isempty(guidance)
        guidance = extraGuidance;
    elseif ~isempty(extraGuidance)
        guidance = sprintf('%s %s', guidance, extraGuidance);
    end
    if ~isempty(guidance)
        uilabel(dialog, ...
            'Text', guidance, ...
            'Position', [20 dialogHeight - 72 580 30], ...
            'FontAngle', 'italic', ...
            'WordWrap', 'on', ...
            'FontColor', [0.36 0.43 0.52]);
    end

    editField = field;
    editField.defaultValue = currentValue;
    control = obj.createInterfaceOptionControl(dialog, editField, [20 dialogHeight - 142 580 controlHeight]);

    response = '';
    uibutton(dialog, 'push', ...
        'Text', 'Cancel', ...
        'Position', [420 20 84 32], ...
        'ButtonPushedFcn', @(~, ~) closeDialog_('cancel'));

    uibutton(dialog, 'push', ...
        'Text', 'Apply', ...
        'Position', [516 20 84 32], ...
        'ButtonPushedFcn', @onApply);

    uiwait(dialog);

    if strcmp(response, 'apply')
        rawValue = obj.readInterfaceControlValue(control, editField);
        cancelled = false;
    else
        rawValue = currentValue;
        cancelled = true;
    end

    if isvalid(dialog)
        delete(dialog);
    end

    function onApply(~, ~)
        try
            value = obj.readInterfaceControlValue(control, editField);
            parsedValue = obj.parseInterfaceOptionValue(editField, value);
            if editField.required && obj.isMissingInterfaceOption(parsedValue)
                error('Missing required option "%s".', editField.label);
            end
            if ~isempty(editField.choices)
                if iscell(parsedValue)
                    if ~all(ismember(parsedValue, editField.choices))
                        error('Option "%s" must use only: %s.', editField.label, strjoin(editField.choices, ', '));
                    end
                elseif ~any(strcmp(char(string(parsedValue)), editField.choices))
                    error('Option "%s" must be one of: %s.', editField.label, strjoin(editField.choices, ', '));
                end
            end
            if strcmp(editField.inputType, 'numeric') && any(isnan(parsedValue))
                error('Option "%s" must be numeric.', editField.label);
            end
        catch ME
            uialert(dialog, ME.message, 'Invalid Interface Option');
            return
        end

        response = 'apply';
        uiresume(dialog);
    end

    function closeDialog_(choice)
        response = choice;
        uiresume(dialog);
    end
end