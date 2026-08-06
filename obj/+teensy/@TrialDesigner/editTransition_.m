function transition = editTransition_(obj, transition, stateIndex)
% transition = editTransition_(obj, transition, stateIndex)
% Modal editor for one transition: its condition, target and actions.
%
% Parameters
%   transition - The transition to edit.
%   stateIndex - Owning state index, passed through to the condition builder.
%
% Returns:
%   transition - The edited transition, or [] if cancelled.
%
% See also: teensy.Transition, teensy.TrialDesigner.editCondition_

arguments
    obj (1,1) teensy.TrialDesigner
    transition (1,1) teensy.Transition
    stateIndex (1,1) double = 0
end

working = transition;

dlg = uifigure(Name = 'Transition', Position = obj.centeredPosition_([520 430]), ...
    Resize = 'off', WindowStyle = 'modal');
closer = onCleanup(@() localSafeDelete_(dlg));

g = uigridlayout(dlg, [6 3]);
g.RowHeight = {30, 30, 30, '1x', 30, 34};
g.ColumnWidth = {110, '1x', 110};
g.Padding = [10 10 10 10];
g.RowSpacing = 5;

% --- Condition ------------------------------------------------------------
lbl = uilabel(g, Text = 'When', HorizontalAlignment = 'right');
lbl.Layout.Row = 1;
lbl.Layout.Column = 1;

condLabel = uilabel(g, Text = '', FontWeight = 'bold', ...
    Tooltip = 'The condition that fires this transition.');
condLabel.Layout.Row = 1;
condLabel.Layout.Column = 2;

condButton = uibutton(g, Text = 'Change...', ...
    Tooltip = 'Open the condition builder.', ...
    ButtonPushedFcn = @(~, ~) localEditCondition_());
condButton.Layout.Row = 1;
condButton.Layout.Column = 3;

% --- Target ---------------------------------------------------------------
lbl = uilabel(g, Text = 'Go to', HorizontalAlignment = 'right');
lbl.Layout.Row = 2;
lbl.Layout.Column = 1;

targets = [{'(stay in this state)'}, cellstr([obj.Program.States.Name])];
current = '(stay in this state)';
if strlength(working.Target) > 0 && any(strcmp(targets, char(working.Target)))
    current = char(working.Target);
end

targetDrop = uidropdown(g, Items = targets, Value = current, ...
    Tooltip = ['Which state to enter. Staying runs the transition''s actions ' ...
               'without resetting the state timer.'], ...
    ValueChangedFcn = @(src, ~) localSetTarget_(src.Value));
targetDrop.Layout.Row = 2;
targetDrop.Layout.Column = [2 3];

% --- Notes ----------------------------------------------------------------
lbl = uilabel(g, Text = 'Notes', HorizontalAlignment = 'right');
lbl.Layout.Row = 3;
lbl.Layout.Column = 1;

notesField = uieditfield(g, 'text', Value = char(working.Notes), ...
    Tooltip = 'Free text describing why this transition exists.', ...
    ValueChangedFcn = @(src, ~) localSetNotes_(src.Value));
notesField.Layout.Row = 3;
notesField.Layout.Column = [2 3];

% --- Actions --------------------------------------------------------------
actionList = uilistbox(g, Items = {}, ...
    Tooltip = ['Actions run as the transition is taken, after the source state''s ' ...
               'exit actions and before the target''s entry actions.']);
actionList.Layout.Row = 4;
actionList.Layout.Column = [1 3];

actionButtons = uigridlayout(g, [1 3]);
actionButtons.Layout.Row = 5;
actionButtons.Layout.Column = [1 3];
actionButtons.ColumnWidth = {'1x', '1x', '1x'};
actionButtons.Padding = [0 0 0 0];

uibutton(actionButtons, Text = 'Add Action', ...
    Tooltip = 'Add an action that runs when this transition fires.', ...
    ButtonPushedFcn = @(~, ~) localAddAction_());
uibutton(actionButtons, Text = 'Edit Action', Tooltip = 'Edit the selected action.', ...
    ButtonPushedFcn = @(~, ~) localEditAction_());
uibutton(actionButtons, Text = 'Remove Action', Tooltip = 'Delete the selected action.', ...
    ButtonPushedFcn = @(~, ~) localRemoveAction_());

buttons = uigridlayout(g, [1 2]);
buttons.Layout.Row = 6;
buttons.Layout.Column = [1 3];
buttons.ColumnWidth = {'1x', '1x'};
buttons.Padding = [0 0 0 0];

uibutton(buttons, Text = 'OK', Tooltip = 'Apply this transition.', ...
    ButtonPushedFcn = @(~, ~) localFinish_(dlg, true));
uibutton(buttons, Text = 'Cancel', Tooltip = 'Discard the changes.', ...
    ButtonPushedFcn = @(~, ~) localFinish_(dlg, false));

localRefresh_();

dlg.CloseRequestFcn = @(~, ~) localFinish_(dlg, false);
uiwait(dlg);

transition = [];
if isvalid(dlg) && isequal(dlg.UserData, true)
    transition = working;
end


% =====================================================================
    function localRefresh_()
        % localRefresh_()
        % Update the condition summary and the action list.
        condLabel.Text = char(working.Condition.describe(obj.Program));

        items = cell(1, numel(working.Actions));
        for i = 1:numel(working.Actions)
            items{i} = char(working.Actions(i).describe());
        end
        actionList.Items = items;
        if ~isempty(items)
            actionList.Value = items{1};
        end
    end

    function localEditCondition_()
        % localEditCondition_()
        % Open the condition builder.
        edited = obj.editCondition_(working.Condition, stateIndex);
        if isempty(edited)
            return
        end
        working.Condition = edited;
        localRefresh_();
    end

    function localSetTarget_(value)
        % localSetTarget_(value)
        % Set the destination state, or "" to stay put.
        if strcmp(value, '(stay in this state)')
            working.Target = "";
        else
            working.Target = string(value);
        end
    end

    function localSetNotes_(value)
        % localSetNotes_(value)
        % Record the transition notes.
        working.Notes = string(value);
    end

    function localAddAction_()
        % localAddAction_()
        % Append a transition action.
        added = obj.editAction_(teensy.Action("SetOutput"));
        if isempty(added)
            return
        end
        working.Actions(end+1) = added;
        localRefresh_();
    end

    function localEditAction_()
        % localEditAction_()
        % Edit the selected transition action.
        idx = localListIndex_(actionList);
        if idx == 0
            return
        end
        edited = obj.editAction_(working.Actions(idx));
        if isempty(edited)
            return
        end
        working.Actions(idx) = edited;
        localRefresh_();
    end

    function localRemoveAction_()
        % localRemoveAction_()
        % Delete the selected transition action.
        idx = localListIndex_(actionList);
        if idx == 0
            return
        end
        working.Actions(idx) = [];
        localRefresh_();
    end
end


% =========================================================================
function idx = localListIndex_(list)
% idx = localListIndex_(list)
% Selected row of a listbox, or 0.
idx = 0;
if isempty(list.Items) || isempty(list.Value)
    return
end
hit = find(strcmp(list.Items, list.Value), 1);
if ~isempty(hit)
    idx = hit;
end
end


function localFinish_(dlg, accepted)
% localFinish_(dlg, accepted)
% Record a modal dialog's result and release the uiwait.
if isvalid(dlg)
    dlg.UserData = accepted;
    uiresume(dlg);
end
end


function localSafeDelete_(dlg)
% localSafeDelete_(dlg)
% Delete a dialog that may already be gone.
if ~isempty(dlg) && isvalid(dlg)
    delete(dlg);
end
end
