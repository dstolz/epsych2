function options = promptForInterfaceOptions(obj, spec, initialOptions, dialogAction)
    if nargin < 3 || isempty(initialOptions)
        initialOptions = struct();
    end
    if nargin < 4 || isempty(dialogAction)
        dialogAction = 'Add Interface';
    end

    fields = spec.options;
    if isempty(fields)
        options = showNoOptionsDialog_(spec, dialogAction);
        return
    end

    dialogHeight = max(320, 220 + 32 * numel(fields));
    dialog = uifigure( ...
        'Name', sprintf('%s: %s', dialogAction, spec.label), ...
        'Position', [240 140 900 dialogHeight], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off');

    uilabel(dialog, ...
        'Text', spec.description, ...
        'Position', [20 dialogHeight - 58 860 34], ...
        'FontAngle', 'italic', ...
        'FontColor', [0.36 0.43 0.52], ...
        'WordWrap', 'on');

    uilabel(dialog, ...
        'Text', 'Select a Value cell to edit it with the control type defined for that option.', ...
        'Position', [20 dialogHeight - 84 860 18], ...
        'FontColor', [0.36 0.43 0.52]);

    tableData = cell(numel(fields), 5);
    rawValues = cell(numel(fields), 1);
    for idx = 1:numel(fields)
        field = fields(idx);
        guidance = field.description;
        extraGuidance = obj.describeInterfaceField(field);
        if isempty(guidance)
            guidance = extraGuidance;
        elseif ~isempty(extraGuidance)
            guidance = sprintf('%s %s', guidance, extraGuidance);
        end

        rawValue = field.defaultValue;
        if isfield(initialOptions, field.name)
            rawValue = initialOptions.(field.name);
        end
        rawValues{idx} = rawValue;

        if field.getFile && field.isList
            inputType = 'file list';
        elseif field.getFile
            inputType = 'file';
        elseif field.getFolder
            inputType = 'folder';
        elseif strcmp(field.inputType, 'choice')
            inputType = 'choice';
        elseif field.isList
            inputType = 'list';
        else
            inputType = char(string(field.inputType));
        end

        tableData{idx, 1} = field.label;
        tableData{idx, 2} = obj.formatInterfaceOptionDisplayValue(field, rawValue);
        tableData{idx, 3} = localRequiredText_(field.required);
        tableData{idx, 4} = inputType;
        tableData{idx, 5} = guidance;
    end

    table = uitable(dialog, ...
        'Position', [20 74 860 dialogHeight - 156], ...
        'ColumnName', {'Option', 'Value', 'Required', 'Input', 'Guidance'}, ...
        'ColumnEditable', false, ...
        'ColumnFormat', {'char', 'char', 'char', 'char', 'char'}, ...
        'ColumnWidth', {180, 250, 76, 90, 236}, ...
        'BackgroundColor', [1 1 1; 0.979 0.984 0.992], ...
        'Data', tableData, ...
        'CellSelectionCallback', @onTableSelectionChanged);

    editButton = uibutton(dialog, 'push', ...
        'Text', 'Edit Selected', ...
        'Position', [20 20 126 32], ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @onEditSelected);

    okPressed = false;
    selectedRow = 0;

    uibutton(dialog, 'push', ...
        'Text', 'Cancel', ...
        'Position', [690 20 90 32], ...
        'ButtonPushedFcn', @(~, ~) close(dialog));

    uibutton(dialog, 'push', ...
        'Text', dialogAction, ...
        'Position', [790 20 90 32], ...
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
        rawValue = rawValues{idx};
        options.(field.name) = obj.parseInterfaceOptionValue(field, rawValue);
    end

    if isvalid(dialog)
        delete(dialog);
    end

    function onOkPressed(~, ~)
        try
            for innerIdx = 1:numel(fields)
                innerField = fields(innerIdx);
                rawValue = rawValues{innerIdx};
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

    function onTableSelectionChanged(~, evt)
        selectedRow = 0;
        editButton.Enable = 'off';
        if isempty(evt.Indices)
            return
        end
        selectedRow = evt.Indices(1, 1);
        if selectedRow >= 1 && selectedRow <= numel(fields)
            editButton.Enable = 'on';
            if size(evt.Indices, 2) >= 2 && evt.Indices(1, 2) == 2
                onEditSelected();
            end
        end
    end

    function onEditSelected(~, ~)
        if selectedRow < 1 || selectedRow > numel(fields)
            return
        end

        field = fields(selectedRow);
        [updatedValue, cancelled] = obj.editInterfaceOptionValue(field, rawValues{selectedRow});
        if cancelled
            return
        end
        rawValues{selectedRow} = updatedValue;
        table.Data{selectedRow, 2} = obj.formatInterfaceOptionDisplayValue(field, updatedValue);
    end
end

function text = localRequiredText_(isRequired)
    if isRequired
        text = 'Required';
    else
        text = 'Optional';
    end
end

function options = showNoOptionsDialog_(spec, dialogAction)
    dialog = uifigure( ...
        'Name', sprintf('%s: %s', dialogAction, spec.label), ...
        'Position', [360 260 520 210], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off');

    uilabel(dialog, ...
        'Text', spec.description, ...
        'Position', [20 128 480 40], ...
        'FontAngle', 'italic', ...
        'FontColor', [0.36 0.43 0.52], ...
        'WordWrap', 'on');

    uilabel(dialog, ...
        'Text', 'This interface has no configurable creation options.', ...
        'Position', [20 86 480 24], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.22 0.28 0.36]);

    response = '';
    uibutton(dialog, 'push', ...
        'Text', 'Cancel', ...
        'Position', [310 22 90 32], ...
        'ButtonPushedFcn', @(~, ~) closeDialog_('cancel'));

    uibutton(dialog, 'push', ...
        'Text', dialogAction, ...
        'Position', [410 22 90 32], ...
        'ButtonPushedFcn', @(~, ~) closeDialog_('apply'));

    uiwait(dialog);

    if strcmp(response, 'apply')
        options = struct();
    else
        options = [];
    end

    if isvalid(dialog)
        delete(dialog);
    end

    function closeDialog_(choice)
        response = choice;
        uiresume(dialog);
    end
end

