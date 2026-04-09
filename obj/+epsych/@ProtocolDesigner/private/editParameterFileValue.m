function [fileValue, cancelled, allowMultiple] = editParameterFileValue(obj, parameter, allowMultiple)
    % editParameterFileValue(obj, parameter, allowMultiple)
    % Open the modal file-value editor for one File parameter.
    % The dialog supports replace, add, remove, and clear actions and
    % returns the final value only when Apply is pressed.
    %
    % Parameters:
    % 	parameter	- File parameter being edited.
    % 	allowMultiple	- True to permit file lists; false for single-file mode.
    %
    % Returns:
    % 	fileValue	- Selected file path or cell array of file paths.
    % 	cancelled	- True when the dialog is dismissed without Apply.
    % 	allowMultiple	- Final single-file or file-list mode after editing.
    currentFiles = obj.getParameterFileList(parameter);
    currentItemPaths = currentFiles;

    dialog = uifigure( ...
        'Name', sprintf('Edit File Values: %s', parameter.Name), ...
        'Position', [220 180 820 470], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off');

    uilabel(dialog, ...
        'Text', sprintf('File values for %s', parameter.Name), ...
        'Position', [20 426 360 22], ...
        'FontSize', 14, ...
        'FontWeight', 'bold');

    if allowMultiple
        summaryText = 'Use Replace to set the list, Add to append more files, or Clear to remove all files.';
    else
        summaryText = 'Use Replace for one file, or Add to select multiple files and switch this parameter to a file list.';
    end
    summaryLabel = uilabel(dialog, ...
        'Text', summaryText, ...
        'Position', [20 400 760 18], ...
        'FontAngle', 'italic');

    countLabel = uilabel(dialog, ...
        'Text', obj.getFileSelectionCountText(currentFiles, allowMultiple), ...
        'Position', [20 372 260 18], ...
        'FontColor', [0.35 0.42 0.52]);

    emptyStateLabel = uilabel(dialog, ...
        'Text', 'No files selected yet.', ...
        'Position', [32 248 240 22], ...
        'FontAngle', 'italic', ...
        'FontColor', [0.45 0.49 0.55], ...
        'Visible', matlab.lang.OnOffSwitchState.off);

    uilabel(dialog, ...
        'Text', 'Selected path(s)', ...
        'Position', [20 102 120 18], ...
        'FontWeight', 'bold', ...
        'FontColor', [0.22 0.28 0.36]);

    pathPreview = uitextarea(dialog, ...
        'Position', [20 20 560 74], ...
        'Editable', 'off', ...
        'Value', {'No files selected.'}, ...
        'BackgroundColor', [0.985 0.988 0.992]);

    listBox = uilistbox(dialog, ...
        'Items', obj.getFileDisplayItems(currentItemPaths), ...
        'Multiselect', 'on', ...
        'Position', [20 122 650 238], ...
        'ValueChangedFcn', @onSelectionChanged);

    uibutton(dialog, 'push', ...
        'Text', 'Replace...', ...
        'Position', [690 300 104 30], ...
        'ButtonPushedFcn', @onReplace);

    uibutton(dialog, 'push', ...
        'Text', 'Add...', ...
        'Position', [690 258 104 30], ...
        'ButtonPushedFcn', @onAdd);

    removeButton = uibutton(dialog, 'push', ...
        'Text', 'Remove Selected', ...
        'Position', [690 216 104 30], ...
        'ButtonPushedFcn', @onRemove);

    clearButton = uibutton(dialog, 'push', ...
        'Text', 'Clear', ...
        'Position', [690 174 104 30], ...
        'ButtonPushedFcn', @onClear);

    uibutton(dialog, 'push', ...
        'Text', 'Cancel', ...
        'Position', [608 20 90 32], ...
        'ButtonPushedFcn', @(~, ~) delete(dialog));

    applied = false;
    uibutton(dialog, 'push', ...
        'Text', 'Apply', ...
        'Position', [706 20 90 32], ...
        'ButtonPushedFcn', @onApply);

    refreshListPresentation();

    uiwait(dialog);

    if ~applied
        fileValue = [];
        cancelled = true;
        if isvalid(dialog)
            delete(dialog);
        end
        return
    end

    finalItems = currentItemPaths;
    if allowMultiple
        fileValue = finalItems;
    else
        if isempty(finalItems)
            fileValue = '';
        else
            fileValue = finalItems{1};
        end
    end

    cancelled = false;
    if isvalid(dialog)
        delete(dialog);
    end

    function onReplace(~, ~)
        [selectedFiles, wasCancelled] = obj.promptForParameterFileValue(parameter, allowMultiple);
        if wasCancelled
            return
        end
        currentItemPaths = obj.normalizeFileValueToList(selectedFiles);
        refreshListPresentation(1);
    end

    function onAdd(~, ~)
        [selectedFiles, wasCancelled] = obj.promptForParameterFileValue(parameter, true);
        if wasCancelled
            return
        end
        newItems = obj.normalizeFileValueToList(selectedFiles);
        if ~allowMultiple && numel(newItems) > 1
            allowMultiple = true;
        end
        currentItemPaths = unique([currentItemPaths, newItems], 'stable');
        selectedIndices = find(ismember(currentItemPaths, newItems));
        refreshListPresentation(selectedIndices);
    end

    function onRemove(~, ~)
        selectedIndices = getSelectedIndices();
        if isempty(selectedIndices)
            return
        end
        currentItemPaths(selectedIndices) = [];
        refreshListPresentation();
    end

    function onClear(~, ~)
        currentItemPaths = {};
        refreshListPresentation();
    end

    function onSelectionChanged(~, ~)
        updateSelectionState();
    end

    function onApply(~, ~)
        if ~allowMultiple && numel(listBox.Items) > 1
            uialert(dialog, 'Only one file can be selected for this parameter.', 'Too Many Files');
            return
        end
        applied = true;
        delete(dialog);
    end

    function refreshListPresentation(selectedIndices)
        if nargin < 1
            selectedIndices = [];
        end

        displayItems = obj.getFileDisplayItems(currentItemPaths);
        listBox.Items = displayItems;

        if isempty(displayItems)
            listBox.Value = {};
        else
            selectedIndices = selectedIndices(selectedIndices >= 1 & selectedIndices <= numel(displayItems));
            if isempty(selectedIndices)
                selectedIndices = 1;
            end
            listBox.Value = displayItems(selectedIndices);
        end

        updateSelectionState();
    end

    function updateSelectionState()
        items = currentItemPaths;
        selectedIndices = getSelectedIndices();
        selectedItems = items(selectedIndices);
        if allowMultiple
            summaryLabel.Text = 'Use Replace to set the list, Add to append more files, or Clear to remove all files.';
        else
            summaryLabel.Text = 'Use Replace for one file, or Add to select multiple files and switch this parameter to a file list.';
        end
        countLabel.Text = obj.getFileSelectionCountText(items, allowMultiple);
        emptyStateLabel.Visible = matlab.lang.OnOffSwitchState(obj.onOffForCondition(isempty(items)));
        removeButton.Enable = matlab.lang.OnOffSwitchState(obj.onOffForCondition(~isempty(selectedItems)));
        clearButton.Enable = matlab.lang.OnOffSwitchState(obj.onOffForCondition(~isempty(items)));
        pathPreview.Value = obj.getFilePreviewLines(selectedItems, items);
    end

    function selectedIndices = getSelectedIndices()
        displayItems = obj.getFileDisplayItems(currentItemPaths);
        selectedLabels = cellstr(listBox.Value);
        selectedIndices = find(ismember(displayItems, selectedLabels));
    end
end

