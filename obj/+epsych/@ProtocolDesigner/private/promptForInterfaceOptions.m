function options = promptForInterfaceOptions(obj, spec)
    fields = spec.options;
    if isempty(fields)
        options = struct();
        return
    end

    dialogHeight = max(220, 120 + 78 * numel(fields));
    dialog = uifigure( ...
        'Name', sprintf('Add %s Interface', spec.label), ...
        'Position', [240 140 620 dialogHeight], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off');

    controls = struct();
    okPressed = false;
    y = dialogHeight - 70;

    for idx = 1:numel(fields)
        field = fields(idx);
        labelText = field.label;
        if field.required
            labelText = [labelText ' *'];
        end

        uilabel(dialog, ...
            'Text', labelText, ...
            'Position', [20 y + 30 180 22], ...
            'FontWeight', 'bold');

        description = field.description;
        extra = obj.describeInterfaceField(field);
        if isempty(description)
            description = extra;
        elseif ~isempty(extra)
            description = sprintf('%s %s', description, extra);
        end

        if ~isempty(description)
            uilabel(dialog, ...
                'Text', description, ...
                'Position', [20 y 580 22], ...
                'FontAngle', 'italic');
        end

        controls.(field.name) = obj.createInterfaceOptionControl(dialog, field, [220 y + 4 370 28]);
        y = y - 78;
    end

    uibutton(dialog, 'push', ...
        'Text', 'Cancel', ...
        'Position', [390 18 90 30], ...
        'ButtonPushedFcn', @(~, ~) close(dialog));

    uibutton(dialog, 'push', ...
        'Text', 'Add Interface', ...
        'Position', [490 18 100 30], ...
        'ButtonPushedFcn', @onOkPressed);

    uiwait(dialog);

    if ~okPressed
        options = [];
        if isvalid(dialog)
            delete(dialog);
        end
        return
    end

    options = struct();
    for idx = 1:numel(fields)
        field = fields(idx);
        rawValue = obj.readInterfaceControlValue(controls.(field.name), field);
        options.(field.name) = obj.parseInterfaceOptionValue(field, rawValue);
    end

    if isvalid(dialog)
        delete(dialog);
    end

    function onOkPressed(~, ~)
        try
            for innerIdx = 1:numel(fields)
                innerField = fields(innerIdx);
                rawValue = obj.readInterfaceControlValue(controls.(innerField.name), innerField);
                value = obj.parseInterfaceOptionValue(innerField, rawValue);
                if innerField.required && obj.isMissingInterfaceOption(value)
                    error('Missing required option "%s".', innerField.label);
                end
                if ~isempty(innerField.choices)
                    if iscell(value)
                        if ~all(ismember(value, innerField.choices))
                            error('Option "%s" must use only: %s.', innerField.label, strjoin(innerField.choices, ', '));
                        end
                    elseif ~any(strcmp(char(string(value)), innerField.choices))
                        error('Option "%s" must be one of: %s.', innerField.label, strjoin(innerField.choices, ', '));
                    end
                end
                if strcmp(innerField.inputType, 'numeric') && any(isnan(value))
                    error('Option "%s" must be numeric.', innerField.label);
                end
            end
        catch ME
            uialert(dialog, ME.message, 'Invalid Interface Options');
            return
        end

        okPressed = true;
        uiresume(dialog);
    end
end

