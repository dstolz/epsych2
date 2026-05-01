function [stimValues, cancelled] = editParameterStimTypeValue(~, parameter)
% [stimValues, cancelled] = editParameterStimTypeValue(obj, parameter)
% Open a modal dialog to add, edit, or remove StimType levels for a parameter.
%
% Parameters:
%   parameter - hw.Parameter with Type 'StimType' being edited.
%
% Returns:
%   stimValues - Cell array of stimgen.StimType objects chosen by the user.
%   cancelled  - True when the dialog is dismissed without applying changes.

cancelled = false;
stimValues = parameter.Values;  % start with existing levels

classList = stimgen.StimType.list();

dialog = uifigure( ...
    'Name', sprintf('Edit StimType Levels: %s', parameter.Name), ...
    'Position', [200 160 700 460], ...
    'WindowStyle', 'modal', ...
    'Resize', 'off');

uilabel(dialog, ...
    'Text', sprintf('Stimulus type levels for  "%s"', parameter.Name), ...
    'Position', [20 422 460 22], ...
    'FontSize', 14, ...
    'FontWeight', 'bold');

uilabel(dialog, ...
    'Text', 'Each row is one trial level. Add a stimulus type from the dropdown, then configure its properties.', ...
    'Position', [20 398 640 18], ...
    'FontAngle', 'italic', ...
    'FontColor', [0.36 0.43 0.52]);

% --- Level list ---
initialItems = localDisplayNames_(stimValues);
listBox = uilistbox(dialog, ...
    'Position', [20 100 320 288], ...
    'Items', initialItems, ...
    'Multiselect', 'off');
if ~isempty(initialItems)
    listBox.Value = initialItems{1};
end

% --- Add controls ---
uilabel(dialog, ...
    'Text', 'Add type:', ...
    'Position', [356 374 70 22], ...
    'FontWeight', 'bold');

dd = uidropdown(dialog, ...
    'Items', classList, ...
    'Value', classList{1}, ...
    'Position', [356 344 200 26]);

btnAdd = uibutton(dialog, 'push', ...
    'Text', 'Add Level', ...
    'Position', [564 344 116 26], ...
    'FontWeight', 'bold', ...
    'Tooltip', 'Create a new StimType of the selected class and append it as a level.');

% --- Edit / Remove ---
btnEdit = uibutton(dialog, 'push', ...
    'Text', 'Edit Selected', ...
    'Position', [356 290 148 28], ...
    'Tooltip', 'Open the property editor for the selected level.', ...
    'Enable', 'off');

btnOpenPlayer = uibutton(dialog, 'push', ...
    'Text', 'Open In StimPlayer', ...
    'Position', [514 290 166 28], ...
    'Tooltip', 'Open the selected StimType level in a new StimPlayer window.', ...
    'Enable', 'off');

btnRemove = uibutton(dialog, 'push', ...
    'Text', 'Remove Selected', ...
    'Position', [356 252 148 28], ...
    'Tooltip', 'Remove the selected level from the list.', ...
    'Enable', 'off');

% --- Apply / Cancel ---
btnApply = uibutton(dialog, 'push', ...
    'Text', 'Apply', ...
    'Position', [478 30 100 32], ...
    'FontWeight', 'bold');

btnCancel = uibutton(dialog, 'push', ...
    'Text', 'Cancel', ...
    'Position', [590 30 100 32]);

% Keep working copy that callbacks modify
workingLevels = stimValues;

% Callbacks
btnAdd.ButtonPushedFcn     = @onAdd;
btnEdit.ButtonPushedFcn    = @onEdit;
btnOpenPlayer.ButtonPushedFcn = @onOpenPlayer;
btnRemove.ButtonPushedFcn  = @onRemove;
listBox.ValueChangedFcn    = @onSelect;
btnApply.ButtonPushedFcn   = @onApply;
btnCancel.ButtonPushedFcn  = @onCancel;

% Block until dialog closes
uiwait(dialog);

% -------------------------------------------------------------------------
    function onAdd(~, ~)
        newStim = feval(sprintf('stimgen.%s', dd.Value));
        workingLevels{end + 1} = newStim;
        updatedItems = localDisplayNames_(workingLevels);
        listBox.Items = updatedItems;
        listBox.Value = updatedItems{end};
        localUpdateButtons_();
    end

    function onEdit(~, ~)
        idx = localSelectedIndex_();
        if isempty(idx), return; end
        edFig = uifigure('Name', sprintf('Edit %s', char(string(workingLevels{idx}.DisplayName))), ...
            'WindowStyle', 'normal');
        workingLevels{idx}.create_gui(edFig);
        updatedItems = localDisplayNames_(workingLevels);
        listBox.Items = updatedItems;
        if idx <= numel(updatedItems)
            listBox.Value = updatedItems{idx};
        end
    end

    function onRemove(~, ~)
        idx = localSelectedIndex_();
        if isempty(idx), return; end
        workingLevels(idx) = [];
        updatedItems = localDisplayNames_(workingLevels);
        listBox.Items = updatedItems;
        if ~isempty(updatedItems)
            listBox.Value = updatedItems{1};
        end
        localUpdateButtons_();
    end

    function onOpenPlayer(~, ~)
        idx = localSelectedIndex_();
        if isempty(idx), return; end
        stim = workingLevels{idx};
        player = stimgen.StimPlayer();
        player.open_stim(stim, Name=string(stim.DisplayName));
    end

    function onSelect(~, ~)
        localUpdateButtons_();
    end

    function onApply(~, ~)
        stimValues = workingLevels;
        delete(dialog);
    end

    function onCancel(~, ~)
        cancelled = true;
        delete(dialog);
    end

    function localUpdateButtons_()
        hasSelection = ~isempty(localSelectedIndex_());
        btnEdit.Enable   = matlab.lang.OnOffSwitchState(hasSelection);
        btnOpenPlayer.Enable = matlab.lang.OnOffSwitchState(hasSelection);
        btnRemove.Enable = matlab.lang.OnOffSwitchState(hasSelection);
    end

    function idx = localSelectedIndex_()
        selectedValue = listBox.Value;
        if isstring(selectedValue)
            selectedValue = char(selectedValue);
        elseif iscell(selectedValue)
            if isempty(selectedValue)
                idx = [];
                return
            end
            selectedValue = selectedValue{1};
        end
        idx = find(strcmp(listBox.Items, selectedValue), 1);
    end
end

% -------------------------------------------------------------------------
function names = localDisplayNames_(levels)
    if isempty(levels)
        names = {};
        return
    end
    names = cellfun(@(v) char(string(v.DisplayName)), levels, 'UniformOutput', false);
    % Make names unique for listbox (append index when duplicates exist)
    for k = 1:numel(names)
        count = sum(strcmp(names(1:k), names{k}));
        if count > 1
            names{k} = sprintf('%s (%d)', names{k}, k);
        end
    end
end
