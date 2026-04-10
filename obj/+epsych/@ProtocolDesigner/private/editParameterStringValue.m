function [stringValue, cancelled, isArrayValue] = editParameterStringValue(~, parameter)
    % editParameterStringValue(obj, parameter)
    % Open the modal string-value editor for one String parameter.
    % Supports one string value or an array of strings using one line per item.
    %
    % Parameters:
    % 	parameter	- String parameter being edited.
    %
    % Returns:
    % 	stringValue	- Final char value or cell array of char values.
    % 	cancelled	- True when the dialog is dismissed without Apply.
    % 	isArrayValue	- True when multiple string entries were applied.
    currentItems = localNormalizeStringItems_(parameter.Value);

    dialog = uifigure( ...
        'Name', sprintf('Edit String Values: %s', parameter.Name), ...
        'Position', [240 190 760 500], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off');

    uilabel(dialog, ...
        'Text', sprintf('String values for %s', parameter.Name), ...
        'Position', [20 458 320 22], ...
        'FontSize', 14, ...
        'FontWeight', 'bold');

    summaryLabel = uilabel(dialog, ...
        'Text', 'Enter one value per line. Apply stores one line as a scalar string and multiple lines as a string array.', ...
        'Position', [20 430 700 18], ...
        'FontAngle', 'italic');

    countLabel = uilabel(dialog, ...
        'Text', localGetCountText_(currentItems), ...
        'Position', [20 404 300 18], ...
        'FontColor', [0.35 0.42 0.52]);

    emptyStateLabel = uilabel(dialog, ...
        'Text', 'No string values entered yet.', ...
        'Position', [34 256 240 22], ...
        'FontAngle', 'italic', ...
        'FontColor', [0.45 0.49 0.55], ...
        'Visible', matlab.lang.OnOffSwitchState.off);

    listBox = uilistbox(dialog, ...
        'Items', currentItems, ...
        'Multiselect', 'on', ...
        'Position', [20 122 430 262], ...
        'ValueChangedFcn', @onSelectionChanged);

    uilabel(dialog, ...
        'Text', 'Add one string per line', ...
        'Position', [470 366 180 18], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.22 0.28 0.36]);

    inputArea = uitextarea(dialog, ...
        'Position', [470 184 250 176], ...
        'Value', {''}, ...
        'BackgroundColor', [0.997 0.998 0.999]);

    uibutton(dialog, 'push', ...
        'Text', 'Add Lines', ...
        'Position', [470 144 110 30], ...
        'ButtonPushedFcn', @onAddLines);

    removeButton = uibutton(dialog, 'push', ...
        'Text', 'Remove Selected', ...
        'Position', [590 144 130 30], ...
        'ButtonPushedFcn', @onRemove);

    clearButton = uibutton(dialog, 'push', ...
        'Text', 'Clear', ...
        'Position', [470 104 110 30], ...
        'ButtonPushedFcn', @onClear);

    uilabel(dialog, ...
        'Text', 'Preview', ...
        'Position', [20 96 80 18], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.22 0.28 0.36]);

    previewArea = uitextarea(dialog, ...
        'Position', [20 20 700 70], ...
        'Editable', 'off', ...
        'Value', {'No string values entered.'}, ...
        'BackgroundColor', [0.985 0.988 0.992]);

    uibutton(dialog, 'push', ...
        'Text', 'Cancel', ...
        'Position', [528 20 90 32], ...
        'ButtonPushedFcn', @(~, ~) delete(dialog));

    applied = false;
    uibutton(dialog, 'push', ...
        'Text', 'Apply', ...
        'Position', [630 20 90 32], ...
        'ButtonPushedFcn', @onApply);

    refreshListPresentation();
    uiwait(dialog);

    if ~applied
        stringValue = [];
        cancelled = true;
        if isvalid(dialog)
            delete(dialog);
        end
        isArrayValue = false;
        return
    end

    if isempty(currentItems)
        stringValue = '';
        isArrayValue = false;
    elseif numel(currentItems) == 1
        stringValue = currentItems{1};
        isArrayValue = false;
    else
        stringValue = currentItems;
        isArrayValue = true;
    end

    cancelled = false;
    if isvalid(dialog)
        delete(dialog);
    end

    function onAddLines(~, ~)
        newItems = localNormalizeStringItems_(inputArea.Value);
        if isempty(newItems)
            uialert(dialog, 'Enter one or more strings in the text box, one per line.', 'No String Values');
            return
        end

        currentItems = [currentItems, newItems];
        inputArea.Value = {''};
        selectedIndices = max(1, numel(currentItems) - numel(newItems) + 1):numel(currentItems);
        refreshListPresentation(selectedIndices);
    end

    function onRemove(~, ~)
        selectedIndices = getSelectedIndices();
        if isempty(selectedIndices)
            return
        end

        currentItems(selectedIndices) = [];
        refreshListPresentation();
    end

    function onClear(~, ~)
        currentItems = {};
        refreshListPresentation();
    end

    function onSelectionChanged(~, ~)
        updateSelectionState();
    end

    function onApply(~, ~)
        applied = true;
        delete(dialog);
    end

    function refreshListPresentation(selectedIndices)
        if nargin < 1
            selectedIndices = [];
        end

        listBox.Items = currentItems;
        if isempty(currentItems)
            listBox.Value = {};
        else
            selectedIndices = selectedIndices(selectedIndices >= 1 & selectedIndices <= numel(currentItems));
            if isempty(selectedIndices)
                selectedIndices = 1;
            end
            listBox.Value = currentItems(selectedIndices);
        end

        updateSelectionState();
    end

    function updateSelectionState()
        selectedIndices = getSelectedIndices();
        selectedItems = currentItems(selectedIndices);
        countLabel.Text = localGetCountText_(currentItems);
        emptyStateLabel.Visible = matlab.lang.OnOffSwitchState(localOnOff_(isempty(currentItems)));
        removeButton.Enable = matlab.lang.OnOffSwitchState(localOnOff_(~isempty(selectedItems)));
        clearButton.Enable = matlab.lang.OnOffSwitchState(localOnOff_(~isempty(currentItems)));
        previewArea.Value = localGetPreviewLines_(selectedItems, currentItems);
        summaryLabel.Text = 'Enter one value per line. Apply stores one line as a scalar string and multiple lines as a string array.';
    end

    function selectedIndices = getSelectedIndices()
        selectedLabels = cellstr(listBox.Value);
        selectedIndices = find(ismember(currentItems, selectedLabels));
    end
end

function items = localNormalizeStringItems_(rawValue)
    if isempty(rawValue)
        items = {};
        return
    end

    if ischar(rawValue)
        items = {strtrim(rawValue)};
    elseif isstring(rawValue)
        items = cellstr(rawValue(:).');
    elseif iscell(rawValue)
        items = {};
        for idx = 1:numel(rawValue)
            item = rawValue{idx};
            if isstring(item)
                item = char(item);
            end
            if ischar(item)
                items{end + 1} = strtrim(item);
            else
                items{end + 1} = strtrim(char(string(item)));
            end
        end
    else
        items = {strtrim(char(string(rawValue)))};
    end

    items = items(~cellfun(@isempty, items));
end

function countText = localGetCountText_(items)
    if isempty(items)
        countText = 'No string values configured.';
    elseif numel(items) == 1
        countText = '1 string value configured.';
    else
        countText = sprintf('%d string values configured.', numel(items));
    end
end

function previewLines = localGetPreviewLines_(selectedItems, allItems)
    if isempty(allItems)
        previewLines = {'No string values entered.'};
        return
    end

    if isempty(selectedItems)
        previewLines = allItems(:).';
    else
        previewLines = selectedItems(:).';
    end
end

function value = localOnOff_(condition)
    if condition
        value = 'on';
    else
        value = 'off';
    end
end