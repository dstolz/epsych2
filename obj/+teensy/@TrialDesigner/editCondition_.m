function condition = editCondition_(obj, condition, stateIndex)
% condition = editCondition_(obj, condition, stateIndex)
% Modal builder for a transition condition.
%
% Two modes. Simple builds one leaf condition, with a field set that rebuilds
% per kind. Combination builds an "all of" or "any of" list whose rows are
% themselves edited by recursing into this same dialog, which is what lets a
% condition nest without a separate expression language.
%
% A plain-English preview updates on every change, because the difference
% between "rises" and "is high" is the difference between a working paradigm
% and a subject that can hold the lever down forever.
%
% Parameters
%   condition  - The condition to edit.
%   stateIndex - Owning state, so the state-timer option can name its duration.
%
% Returns:
%   condition - The edited condition, or [] if cancelled.
%
% See also: teensy.Condition, teensy.TrialDesigner.editTransition_

arguments
    obj (1,1) teensy.TrialDesigner
    condition (1,1) teensy.Condition
    stateIndex (1,1) double = 0
end

working = condition;

dlg = uifigure(Name = 'When should this transition fire?', ...
    Position = obj.centeredPosition_([520 470]), Resize = 'off', WindowStyle = 'modal');

g = uigridlayout(dlg, [5 2]);
g.RowHeight = {30, 30, '1x', 44, 34};
g.ColumnWidth = {130, '1x'};
g.Padding = [10 10 10 10];

lbl = uilabel(g, Text = 'Condition', HorizontalAlignment = 'right');
lbl.Layout.Row = 1;
lbl.Layout.Column = 1;

modeDrop = uidropdown(g, ...
    Items = {'a single condition', 'all of several', 'any of several'}, ...
    Tooltip = ['A single test, or a combination. Combinations nest: each row can ' ...
               'itself be a combination.']);
modeDrop.Layout.Row = 1;
modeDrop.Layout.Column = 2;

kindLabel = uilabel(g, Text = 'Test', HorizontalAlignment = 'right');
kindLabel.Layout.Row = 2;
kindLabel.Layout.Column = 1;

kindDrop = uidropdown(g, ...
    Items = localKindItems_(), ...
    Tooltip = 'What kind of event or state this condition tests.');
kindDrop.Layout.Row = 2;
kindDrop.Layout.Column = 2;

body = uipanel(g, BorderType = 'none');
body.Layout.Row = 3;
body.Layout.Column = [1 2];

preview = uilabel(g, Text = '', FontAngle = 'italic', WordWrap = 'on', ...
    FontColor = obj.COLOR_HINT);
preview.Layout.Row = 4;
preview.Layout.Column = [1 2];

buttons = uigridlayout(g, [1 2]);
buttons.Layout.Row = 5;
buttons.Layout.Column = [1 2];
buttons.ColumnWidth = {'1x', '1x'};
buttons.Padding = [0 0 0 0];

okButton = uibutton(buttons, Text = 'OK', Tooltip = 'Use this condition.', ...
    ButtonPushedFcn = @(~, ~) localFinish_(dlg, true));
uibutton(buttons, Text = 'Cancel', Tooltip = 'Discard the changes.', ...
    ButtonPushedFcn = @(~, ~) localFinish_(dlg, false));

modeDrop.Value = localModeOf_(working);
if ismember(working.Kind, teensy.Condition.LeafKinds)
    kindDrop.Value = localKindLabel_(working.Kind);
end

modeDrop.ValueChangedFcn = @(src, ~) localModeChanged_(src.Value);
kindDrop.ValueChangedFcn = @(src, ~) localKindChanged_(src.Value);

localRebuild_();

dlg.CloseRequestFcn = @(~, ~) localFinish_(dlg, false);
uiwait(dlg);

% Delete the dialog here rather than from an onCleanup: the nested functions
% below are wired as callbacks on the dialog's own children, so this workspace
% stays alive exactly as long as the dialog does. An onCleanup would be waiting
% on the deletion it was supposed to perform, and the dialog would never close.
condition = [];
if isvalid(dlg)
    if isequal(dlg.UserData, true)
        condition = working;
    end
    delete(dlg);
end


% =====================================================================
    function localModeChanged_(mode)
        % localModeChanged_(mode)
        % Switch between a single condition and a combination.
        switch mode
            case 'all of several'
                if ~ismember(working.Kind, ["And", "Or"])
                    working = teensy.Condition.all([working, teensy.Condition.always()]);
                else
                    working.Kind = "And";
                end
            case 'any of several'
                if ~ismember(working.Kind, ["And", "Or"])
                    working = teensy.Condition.any([working, teensy.Condition.always()]);
                else
                    working.Kind = "Or";
                end
            otherwise
                if ismember(working.Kind, ["And", "Or"]) && ~isempty(working.Operands)
                    working = working.Operands(1);
                end
        end
        localRebuild_();
    end

    function localKindChanged_(label)
        % localKindChanged_(label)
        % Switch a leaf condition's kind, keeping sensible defaults.
        kind = localKindFromLabel_(label);
        rebuilt = teensy.Condition(kind);

        % Carry over the channel when the new kind can still use it.
        if strlength(working.Channel) > 0
            rebuilt.Channel = working.Channel;
        end
        rebuilt.Timer = working.Timer;
        rebuilt.Counter = working.Counter;

        working = rebuilt;
        localRebuild_();
    end

    function localSetField_(name, value)
        % localSetField_(name, value)
        % Write one field and refresh the preview.
        working.(name) = value;
        preview.Text = char(working.describe(obj.Program));
    end

    function localRebuild_()
        % localRebuild_()
        % Build the controls the current mode and kind need.
        delete(body.Children);

        isCombo = ismember(working.Kind, ["And", "Or"]);
        kindLabel.Visible = matlab.lang.OnOffSwitchState(~isCombo);
        kindDrop.Visible = matlab.lang.OnOffSwitchState(~isCombo);

        if isCombo
            localBuildCombination_();
        else
            localBuildLeaf_();
        end

        preview.Text = char(working.describe(obj.Program));
        okButton.Enable = matlab.lang.OnOffSwitchState(localIsComplete_(working));
    end

    function localBuildCombination_()
        % localBuildCombination_()
        % A list of sub-conditions, each editable by recursion.
        cg = uigridlayout(body, [2 1]);
        cg.RowHeight = {'1x', 32};
        cg.Padding = [0 4 0 0];

        items = cell(1, numel(working.Operands));
        for i = 1:numel(working.Operands)
            items{i} = char(working.Operands(i).describe(obj.Program));
        end

        list = uilistbox(cg, Items = items, ...
            Tooltip = 'Double-click a row to edit it. Each row may itself be a combination.');
        list.Layout.Row = 1;
        if ~isempty(items)
            list.Value = items{1};
        end
        list.DoubleClickedFcn = @(src, ~) localEditOperand_(src);

        rowButtons = uigridlayout(cg, [1 3]);
        rowButtons.Layout.Row = 2;
        rowButtons.ColumnWidth = {'1x', '1x', '1x'};
        rowButtons.Padding = [0 0 0 0];

        uibutton(rowButtons, Text = 'Add', Tooltip = 'Add another sub-condition.', ...
            ButtonPushedFcn = @(~, ~) localAddOperand_());
        uibutton(rowButtons, Text = 'Edit', Tooltip = 'Edit the selected sub-condition.', ...
            ButtonPushedFcn = @(~, ~) localEditOperand_(list));
        uibutton(rowButtons, Text = 'Remove', Tooltip = 'Delete the selected sub-condition.', ...
            ButtonPushedFcn = @(~, ~) localRemoveOperand_(list));
    end

    function localAddOperand_()
        % localAddOperand_()
        % Append a sub-condition, edited by recursing into this dialog.
        if numel(working.Operands) >= teensy.Compiler.LIMITS.MAX_STACK_DEPTH
            uialert(dlg, sprintf( ...
                ['A combination can hold at most %d parts, because the firmware ' ...
                 'evaluator stack is that deep.'], teensy.Compiler.LIMITS.MAX_STACK_DEPTH), ...
                'Too Many Parts', Icon = 'warning');
            return
        end

        added = obj.editCondition_(teensy.Condition.always(), stateIndex);
        if isempty(added)
            return
        end
        working.Operands(end+1) = added;
        localRebuild_();
    end

    function localEditOperand_(list)
        % localEditOperand_(list)
        % Edit the selected sub-condition.
        idx = localListIndex_(list);
        if idx == 0
            return
        end

        edited = obj.editCondition_(working.Operands(idx), stateIndex);
        if isempty(edited)
            return
        end
        working.Operands(idx) = edited;
        localRebuild_();
    end

    function localRemoveOperand_(list)
        % localRemoveOperand_(list)
        % Delete the selected sub-condition.
        idx = localListIndex_(list);
        if idx == 0
            return
        end
        working.Operands(idx) = [];
        localRebuild_();
    end

    function localBuildLeaf_()
        % localBuildLeaf_()
        % Build the field set for a single condition kind.
        fields = localFieldsFor_(working.Kind);
        nRows = max(size(fields, 1), 1);

        fg = uigridlayout(body, [nRows, 3]);
        fg.RowHeight = repmat({28}, 1, nRows);
        fg.ColumnWidth = {130, '1x', 110};
        fg.Padding = [0 4 0 0];
        fg.RowSpacing = 4;
        fg.Scrollable = 'on';

        varNames = localVarNames_(obj.Program);

        for r = 1:size(fields, 1)
            name = fields{r, 1};
            label = fields{r, 2};
            kind = fields{r, 3};
            tip = fields{r, 4};

            l = uilabel(fg, Text = label, HorizontalAlignment = 'right', Tooltip = tip);
            l.Layout.Row = r;
            l.Layout.Column = 1;

            switch kind
                case 'channelDigital'
                    items = localChannelNames_(obj.Program, "Input", "Digital");
                    h = localDropdown_(fg, items, working.Channel, tip, ...
                        @(v) localSetField_('Channel', string(v)));

                case 'channelAnalog'
                    items = localChannelNames_(obj.Program, "Input", "Analog");
                    h = localDropdown_(fg, items, working.Channel, tip, ...
                        @(v) localSetField_('Channel', string(v)));

                case 'timer'
                    items = localAuxNames_(obj.Program.GlobalTimers);
                    h = localDropdown_(fg, items, working.Timer, tip, ...
                        @(v) localSetField_('Timer', string(v)));

                case 'counter'
                    items = localAuxNames_(obj.Program.Counters);
                    h = localDropdown_(fg, items, working.Counter, tip, ...
                        @(v) localSetField_('Counter', string(v)));

                case 'edge'
                    h = localDropdown_(fg, {'Rising', 'Falling', 'Either'}, ...
                        working.Edge, tip, @(v) localSetField_('Edge', string(v)));

                case 'compare'
                    h = localDropdown_(fg, {'Above', 'Below', 'CrossUp', 'CrossDown'}, ...
                        working.Compare, tip, @(v) localSetField_('Compare', string(v)));

                case 'compareOp'
                    h = localDropdown_(fg, {'GE', 'GT', 'LE', 'LT', 'EQ'}, ...
                        working.CompareOp, tip, @(v) localSetField_('CompareOp', string(v)));

                case 'level'
                    h = localDropdown_(fg, {'1', '0'}, string(working.Level), tip, ...
                        @(v) localSetField_('Level', str2double(v)));

                otherwise
                    h = uieditfield(fg, 'numeric', ...
                        Value = obj.Program.resolve(working.(name)), Tooltip = tip, ...
                        ValueChangedFcn = @(src, ~) localSetField_(name, src.Value));
            end

            h.Layout.Row = r;
            h.Layout.Column = 2;

            if strcmp(kind, 'numeric')
                [isRef, refName] = teensy.isVarRef(working.(name));
                current = 'literal';
                if isRef
                    current = char(refName);
                    h.Enable = 'off';
                end

                vd = uidropdown(fg, Items = [{'literal'}, cellstr(varNames)], ...
                    Value = current, ...
                    Tooltip = 'Drive this from a variable so a protocol can vary it per trial.', ...
                    ValueChangedFcn = @(src, ~) localUseVariable_(name, src.Value));
                vd.Layout.Row = r;
                vd.Layout.Column = 3;
            end
        end

        if size(fields, 1) == 0
            hintText = 'This condition needs no settings.';
            if working.Kind == "StateTimer" && stateIndex > 0
                hintText = sprintf('Fires when the state has run for its duration (%s).', ...
                    localDurationText_(obj.Program, stateIndex));
            end
            uilabel(fg, Text = hintText, FontAngle = 'italic', WordWrap = 'on', ...
                FontColor = obj.COLOR_HINT);
        end
    end

    function localUseVariable_(name, choice)
        % localUseVariable_(name, choice)
        % Swap a field between a literal and a variable reference.
        if strcmp(choice, 'literal')
            working.(name) = obj.Program.resolve(working.(name));
        else
            working.(name) = teensy.varRef(choice);
        end
        localRebuild_();
    end
end


% =========================================================================
function items = localKindItems_()
% items = localKindItems_()
% Human-readable labels for the leaf condition kinds, in a sensible order.
items = { ...
    'the state timer runs out', ...
    'an input changes (edge)', ...
    'an input is held at a level', ...
    'an analog input crosses a threshold', ...
    'a counter reaches a value', ...
    'a global timer expires', ...
    'a random draw (probability)', ...
    'always', ...
    'never'};
end


function kind = localKindFromLabel_(label)
% kind = localKindFromLabel_(label)
% Map a human label back onto a teensy.Condition kind.
switch label
    case 'the state timer runs out',             kind = "StateTimer";
    case 'an input changes (edge)',              kind = "DigitalEdge";
    case 'an input is held at a level',          kind = "DigitalLevel";
    case 'an analog input crosses a threshold',  kind = "AnalogThreshold";
    case 'a counter reaches a value',            kind = "Counter";
    case 'a global timer expires',               kind = "GlobalTimer";
    case 'a random draw (probability)',          kind = "Probability";
    case 'never',                                kind = "Never";
    otherwise,                                   kind = "Always";
end
end


function label = localKindLabel_(kind)
% label = localKindLabel_(kind)
% Map a teensy.Condition kind onto its human label.
items = localKindItems_();
for i = 1:numel(items)
    if localKindFromLabel_(items{i}) == kind
        label = items{i};
        return
    end
end
label = 'always';
end


function mode = localModeOf_(condition)
% mode = localModeOf_(condition)
% Which dialog mode a condition belongs in.
switch condition.Kind
    case "And", mode = 'all of several';
    case "Or",  mode = 'any of several';
    otherwise,  mode = 'a single condition';
end
end


function fields = localFieldsFor_(kind)
% fields = localFieldsFor_(kind)
% The settings one condition kind needs: {property, label, kind, tooltip}.
switch kind
    case "DigitalEdge"
        fields = {
            'Channel', 'Input', 'channelDigital', 'Which input to watch.'
            'Edge', 'Edge', 'edge', ...
                'Rising fires as the input becomes active; falling as it is released.'};

    case "DigitalLevel"
        fields = {
            'Channel', 'Input', 'channelDigital', 'Which input to watch.'
            'Level', 'Level', 'level', '1 means active, 0 means inactive.'
            'HoldMs', 'Held for (ms)', 'numeric', ...
                'The level must persist this long. 0 fires as soon as the level matches.'};

    case "AnalogThreshold"
        fields = {
            'Channel', 'Input', 'channelAnalog', 'Which analog input to watch.'
            'Compare', 'Test', 'compare', ...
                ['Above and Below test the current level; CrossUp and CrossDown fire ' ...
                 'once on the transition.']
            'Threshold', 'Threshold', 'numeric', ...
                'In the channel''s engineering units. The channel''s hysteresis still applies.'
            'HoldMs', 'Held for (ms)', 'numeric', 'The condition must persist this long.'};

    case "Counter"
        fields = {
            'Counter', 'Counter', 'counter', 'Which counter to test.'
            'CompareOp', 'Comparison', 'compareOp', 'How to compare the count.'
            'Count', 'Count', 'numeric', 'The value to compare against.'};

    case "GlobalTimer"
        fields = {'Timer', 'Timer', 'timer', 'Which global timer must have expired.'};

    case "Probability"
        fields = {'Probability', 'Chance (0-1)', 'numeric', ...
            ['How often this branch is taken. Drive it from a variable to control ' ...
             'the mix from the trial table.']};

    case "StateTimer"
        fields = {'HoldMs', 'After (ms)', 'numeric', ...
            'Fire this long after entering the state. 0 uses the state''s own duration.'};

    otherwise
        fields = cell(0, 4);
end
end


function tf = localIsComplete_(condition)
% tf = localIsComplete_(condition)
% Whether a condition has everything it needs to be used.
switch condition.Kind
    case {"DigitalEdge", "DigitalLevel", "AnalogThreshold"}
        tf = strlength(condition.Channel) > 0;
    case "Counter"
        tf = strlength(condition.Counter) > 0;
    case "GlobalTimer"
        tf = strlength(condition.Timer) > 0;
    case {"And", "Or"}
        tf = numel(condition.Operands) >= 2 && ...
            all(arrayfun(@localIsComplete_, condition.Operands));
    otherwise
        tf = true;
end
end


function txt = localDurationText_(program, stateIndex)
% txt = localDurationText_(program, stateIndex)
% The owning state's duration, in words.
value = program.States(stateIndex).DurationMs;
[isRef, refName] = teensy.isVarRef(value);

if isRef
    txt = sprintf('the %s variable, currently %g ms', refName, program.resolve(value));
elseif isfinite(value)
    txt = sprintf('%g ms', value);
else
    txt = 'no duration set, so this will never fire';
end
end


function h = localDropdown_(parent, items, value, tip, setter)
% h = localDropdown_(parent, items, value, tip, setter)
% A dropdown that tolerates a current value not in the list.
if isempty(items)
    items = {'(none)'};
end

current = char(value);
if isempty(current) || ~any(strcmp(items, current))
    current = items{1};
    if ~strcmp(current, '(none)')
        setter(current);
    end
end

h = uidropdown(parent, Items = items, Value = current, Tooltip = tip, ...
    ValueChangedFcn = @(src, ~) setter(src.Value));
end


function names = localChannelNames_(program, direction, kind)
% names = localChannelNames_(program, direction, kind)
% Channel names filtered by direction and kind.
names = {};
for i = 1:numel(program.Channels)
    c = program.Channels(i);
    if c.Direction == direction && c.Kind == kind
        names{end+1} = char(c.Name);
    end
end
end


function names = localAuxNames_(structArray)
% names = localAuxNames_(structArray)
% Names from a timer or counter struct array.
names = {};
for i = 1:numel(structArray)
    names{end+1} = char(structArray(i).Name);
end
end


function names = localVarNames_(program)
% names = localVarNames_(program)
% Variable names as a string array.
if isempty(program.Variables)
    names = strings(1, 0);
else
    names = [program.Variables.Name];
end
end


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
