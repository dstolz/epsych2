function action = editAction_(obj, action)
% action = editAction_(obj, action)
% Modal editor for one teensy.Action.
%
% The field set rebuilds whenever the Kind changes, because the operands of a
% pulse train and of an add-response-code have nothing in common and showing
% the union of them makes the dialog unreadable.
%
% Every numeric field is paired with a variable dropdown: choosing a variable
% stores an "@Name" reference instead of a literal, which is how a duration
% becomes something a protocol can vary per trial.
%
% Parameters
%   action - The action to edit. Pass a default-constructed one to add.
%
% Returns:
%   action - The edited action, or [] if cancelled.
%
% See also: teensy.Action, teensy.TrialDesigner.editCondition_

arguments
    obj (1,1) teensy.TrialDesigner
    action (1,1) teensy.Action
end

working = action;

dlg = uifigure(Name = 'Action', Position = obj.centeredPosition_([470 430]), ...
    Resize = 'off', WindowStyle = 'modal');
closer = onCleanup(@() localSafeDelete_(dlg));

g = uigridlayout(dlg, [4 2]);
g.RowHeight = {30, '1x', 30, 34};
g.ColumnWidth = {120, '1x'};
g.Padding = [10 10 10 10];

lbl = uilabel(g, Text = 'Do what', HorizontalAlignment = 'right');
lbl.Layout.Row = 1;
lbl.Layout.Column = 1;

kindDrop = uidropdown(g, ...
    Items = cellstr(teensy.Action.Kinds), ...
    Value = char(working.Kind), ...
    Tooltip = 'What this action does when it runs.');
kindDrop.Layout.Row = 1;
kindDrop.Layout.Column = 2;

fieldPanel = uipanel(g, BorderType = 'none');
fieldPanel.Layout.Row = 2;
fieldPanel.Layout.Column = [1 2];

preview = uilabel(g, Text = '', FontAngle = 'italic', WordWrap = 'on', ...
    FontColor = obj.COLOR_HINT);
preview.Layout.Row = 3;
preview.Layout.Column = [1 2];

buttons = uigridlayout(g, [1 2]);
buttons.Layout.Row = 4;
buttons.Layout.Column = [1 2];
buttons.ColumnWidth = {'1x', '1x'};
buttons.Padding = [0 0 0 0];

uibutton(buttons, Text = 'OK', Tooltip = 'Apply this action.', ...
    ButtonPushedFcn = @(~, ~) localFinish_(dlg, true));
uibutton(buttons, Text = 'Cancel', Tooltip = 'Discard the changes.', ...
    ButtonPushedFcn = @(~, ~) localFinish_(dlg, false));

kindDrop.ValueChangedFcn = @(src, ~) localKindChanged_(src.Value);

localRebuild_();

dlg.CloseRequestFcn = @(~, ~) localFinish_(dlg, false);
uiwait(dlg);

action = [];
if isvalid(dlg) && isequal(dlg.UserData, true)
    action = working;
end


% =====================================================================
    function localKindChanged_(kind)
        % localKindChanged_(kind)
        % Switch the action kind and rebuild the field set.
        working.Kind = string(kind);
        localRebuild_();
    end

    function localSetField_(name, value)
        % localSetField_(name, value)
        % Write one operand and refresh the plain-English preview.
        working.(name) = value;
        preview.Text = char(working.describe());
    end

    function localRebuild_()
        % localRebuild_()
        % Build the controls this action kind needs.
        delete(fieldPanel.Children);

        fields = localFieldsFor_(working.Kind);
        nRows = max(size(fields, 1), 1);

        fg = uigridlayout(fieldPanel, [nRows, 3]);
        fg.RowHeight = repmat({28}, 1, nRows);
        fg.ColumnWidth = {120, '1x', 110};
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
                case 'channelOut'
                    items = localChannelNames_(obj.Program, "Output");
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

                case 'variable'
                    items = cellstr(varNames);
                    h = localDropdown_(fg, items, working.Variable, tip, ...
                        @(v) localSetField_('Variable', string(v)));

                case 'text'
                    h = uieditfield(fg, 'text', Value = char(working.(name)), ...
                        Tooltip = tip, ...
                        ValueChangedFcn = @(src, ~) localSetField_(name, string(src.Value)));

                case 'bits'
                    h = uibutton(fg, Text = localBitsLabel_(working.Bits), Tooltip = tip, ...
                        ButtonPushedFcn = @(src, ~) localPickBits_(src));

                otherwise
                    h = uieditfield(fg, 'numeric', ...
                        Value = obj.Program.resolve(working.(name)), Tooltip = tip, ...
                        ValueChangedFcn = @(src, ~) localSetField_(name, src.Value));
            end

            h.Layout.Row = r;
            h.Layout.Column = 2;

            % Numeric operands can be driven from a variable instead.
            if strcmp(kind, 'numeric')
                [isRef, refName] = teensy.isVarRef(working.(name));
                current = 'literal';
                if isRef
                    current = char(refName);
                    h.Enable = 'off';
                end

                vd = uidropdown(fg, Items = [{'literal'}, cellstr(varNames)], ...
                    Value = current, ...
                    Tooltip = ['Drive this from a variable so a protocol can vary it ' ...
                               'per trial.'], ...
                    ValueChangedFcn = @(src, ~) localUseVariable_(name, src.Value));
                vd.Layout.Row = r;
                vd.Layout.Column = 3;
            end
        end

        if size(fields, 1) == 0
            uilabel(fg, Text = 'This action has no settings.', FontAngle = 'italic', ...
                FontColor = obj.COLOR_HINT);
        end

        preview.Text = char(working.describe());
    end

    function localUseVariable_(name, choice)
        % localUseVariable_(name, choice)
        % Swap an operand between a literal and a variable reference.
        if strcmp(choice, 'literal')
            working.(name) = obj.Program.resolve(working.(name));
        else
            working.(name) = teensy.varRef(choice);
        end
        localRebuild_();
    end

    function localPickBits_(src)
        % localPickBits_(src)
        % Pick response-code bits for an AddRespCode action.
        mask = obj.pickBitMask_(working.respMask(), 'this action');
        if isempty(mask)
            return
        end

        [~, bits] = epsych.BitMask.Mask2Bits(uint32(mask), 32);
        working.Bits = reshape(bits{1}, 1, []);
        src.Text = localBitsLabel_(working.Bits);
        preview.Text = char(working.describe());
    end
end


% =========================================================================
function fields = localFieldsFor_(kind)
% fields = localFieldsFor_(kind)
% The operands one action kind needs: {property, label, kind, tooltip}.
switch kind
    case "SetOutput"
        fields = {
            'Channel', 'Output', 'channelOut', 'Which output to drive.'
            'Value', 'Level', 'numeric', '1 drives it high, 0 drives it low.'};

    case "Pulse"
        fields = {
            'Channel', 'Output', 'channelOut', 'Which output to pulse.'
            'WidthMs', 'Width (ms)', 'numeric', 'How long the pulse stays high.'
            'DelayMs', 'Delay (ms)', 'numeric', 'Wait this long before the pulse starts.'};

    case "PulseTrain"
        fields = {
            'Channel', 'Output', 'channelOut', 'Which output to pulse.'
            'WidthMs', 'Width (ms)', 'numeric', 'How long each pulse stays high.'
            'PeriodMs', 'Period (ms)', 'numeric', 'Time from one pulse onset to the next.'
            'Count', 'Count', 'numeric', 'How many pulses in the train.'};

    case "AnalogOut"
        fields = {
            'Channel', 'Output', 'channelOut', 'Which analog output to drive.'
            'Value', 'Level', 'numeric', 'Output level in engineering units.'};

    case "StartTimer"
        fields = {
            'Timer', 'Timer', 'timer', 'Which global timer to start.'
            'Value', 'Override (ms)', 'numeric', ...
                'Run for this long instead of the timer''s configured duration. 0 uses the default.'};

    case "CancelTimer"
        fields = {'Timer', 'Timer', 'timer', 'Which global timer to stop.'};

    case "ResetCounter"
        fields = {'Counter', 'Counter', 'counter', 'Which counter to clear.'};

    case "IncrementCounter"
        fields = {
            'Counter', 'Counter', 'counter', 'Which counter to advance.'
            'Value', 'Step', 'numeric', 'How much to add.'};

    case "AddRespCode"
        fields = {'Bits', 'Outcome bits', 'bits', ...
            'Response-code bits to add to this trial''s RespCode.'};

    case "LogEvent"
        fields = {
            'EventName', 'Event name', 'text', 'Name recorded in the event log.'
            'Value', 'Value', 'numeric', 'Number recorded alongside the name.'};

    case "SetVariable"
        fields = {
            'Variable', 'Variable', 'variable', 'Which variable to write.'
            'Value', 'Value', 'numeric', 'The value to store.'};

    case "Sync"
        fields = {
            'Channel', 'Output', 'channelOut', 'Which output carries the sync pulse.'
            'WidthMs', 'Width (ms)', 'numeric', 'How long the sync pulse stays high.'};

    otherwise
        % MarkLatency and EndTrial take no operands.
        fields = cell(0, 4);
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
    setter(current);
end

h = uidropdown(parent, Items = items, Value = current, Tooltip = tip, ...
    ValueChangedFcn = @(src, ~) setter(src.Value));
end


function names = localChannelNames_(program, direction)
% names = localChannelNames_(program, direction)
% Channel names filtered by direction.
names = {};
for i = 1:numel(program.Channels)
    if program.Channels(i).Direction == direction
        names{end+1} = char(program.Channels(i).Name);
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


function txt = localBitsLabel_(bits)
% txt = localBitsLabel_(bits)
% Button text summarizing a bit selection.
if isempty(bits)
    txt = '(none) - click to pick';
else
    txt = char(strjoin(string(bits), ' + '));
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
