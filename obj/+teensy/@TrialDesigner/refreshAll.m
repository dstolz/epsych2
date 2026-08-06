function refreshAll(obj)
% refreshAll(obj)
% Redraw every tab from the current program.
%
% The designer refreshes wholesale rather than patching individual controls.
% A program edit can change several tabs at once -- renaming a channel
% rewrites conditions on the States tab and rows on the Variables tab -- and
% a full refresh cannot get out of step with the model.
%
% See also: teensy.TrialDesigner.drawDiagram

arguments
    obj (1,1) teensy.TrialDesigner
end

if isempty(obj.Figure) || ~isvalid(obj.Figure)
    return
end

localRefreshChannels_(obj);
localRefreshStates_(obj);
localRefreshVariables_(obj);
localRefreshSimulate_(obj);
localRefreshCompile_(obj);
localRefreshChrome_(obj);

obj.drawDiagram();
end


% =========================================================================
function localRefreshChannels_(obj)
% localRefreshChannels_(obj)
% Channel table, inspector and pin picker.
C = obj.Program.Channels;
n = numel(C);

data = cell(n, 11);
for i = 1:n
    data(i, :) = {char(C(i).Name), char(C(i).Direction), char(C(i).Kind), ...
        C(i).Pin, C(i).ActiveHigh, C(i).DebounceMs, C(i).ThresholdHigh, ...
        C(i).ThresholdLow, C(i).IdleState, char(C(i).Units), char(C(i).Notes)};
end
obj.HChannels.Table.Data = data;

% Tint rows that have an error, so a bad pin is visible without opening the
% Compile tab.
removeStyle(obj.HChannels.Table);
badRows = [];
for i = 1:n
    iss = C(i).validate(obj.Program);
    if teensy.Compiler.hasError(iss)
        badRows(end+1) = i;
    end
end
if ~isempty(badRows)
    addStyle(obj.HChannels.Table, ...
        uistyle(BackgroundColor = obj.SEVERITY_COLORS.error), 'row', badRows);
end

idx = obj.SelectedChannel;
hasSelection = idx >= 1 && idx <= n;

delete(obj.HChannels.InspectorPanel.Children);

if ~hasSelection
    g = uigridlayout(obj.HChannels.InspectorPanel, [1 1]);
    uilabel(g, Text = 'Select a channel to edit it.', ...
        FontAngle = 'italic', FontColor = obj.COLOR_HINT);
    obj.HChannels.PinDrop.Items = {'(none)'};
    obj.HChannels.PinNote.Text = '';
    localSetEnable_(obj.HChannels, {'LivePulse', 'LiveOn', 'LiveOff'}, 'off');
    return
end

c = C(idx);
localBuildChannelInspector_(obj, c);
localRefreshPinPicker_(obj, c, idx);

isLiveOutput = c.Direction == "Output" && ~isempty(obj.Interface) && ...
    isa(obj.Interface, 'hw.Teensy') && obj.Interface.IsConnected;
localSetEnable_(obj.HChannels, {'LivePulse', 'LiveOn', 'LiveOff'}, ...
    matlab.lang.OnOffSwitchState(isLiveOutput));
end


function localBuildChannelInspector_(obj, c)
% localBuildChannelInspector_(obj, c)
% Build the field set that matches this channel's direction and kind.
%
% Rebuilt on every selection change rather than showing a superset of
% controls, because the fields that matter for a digital input and an analog
% output have almost nothing in common.
fields = {'Name', char(c.Name), 'text', 'Logical name used in conditions and actions.'};

if c.Direction == "Input" && c.Kind == "Digital"
    fields(end+1, :) = {'DebounceMs', c.DebounceMs, 'numeric', ...
        'A change is accepted only after the raw level has held this long.'};
    fields(end+1, :) = {'ActiveHigh', c.ActiveHigh, 'logical', ...
        'Clear this for a switch that pulls the pin low when active.'};
    fields(end+1, :) = {'PullMode', char(c.PullMode), 'choice:None|PullUp|PullDown', ...
        'Internal pull resistor. A floating input reads as noise.'};

elseif c.Direction == "Input"
    fields(end+1, :) = {'ThresholdHigh', c.ThresholdHigh, 'numeric', ...
        'The value at which the input is considered active.'};
    fields(end+1, :) = {'ThresholdLow', c.ThresholdLow, 'numeric', ...
        'The value at which it goes inactive again. Keep it below the high threshold.'};
    fields(end+1, :) = {'Units', char(c.Units), 'text', 'Engineering units for the thresholds.'};
    fields(end+1, :) = {'Scale', c.Scale, 'numeric', 'Counts to units: units = counts*Scale + Offset.'};
    fields(end+1, :) = {'Offset', c.Offset, 'numeric', 'Zero offset in engineering units.'};
    fields(end+1, :) = {'SampleRateHz', c.SampleRateHz, 'numeric', 'How often the board samples it.'};

elseif c.Kind == "Digital"
    fields(end+1, :) = {'IdleState', c.IdleState, 'numeric', ...
        'Level the output rests at outside a trial. A house light that is normally on rests at 1.'};
    fields(end+1, :) = {'ActiveHigh', c.ActiveHigh, 'logical', ...
        'Clear this for hardware driven by an active-low signal.'};

else
    fields(end+1, :) = {'AnalogOutMode', char(c.AnalogOutMode), 'choice:PWM|MQS|SPI_DAC', ...
        'Teensy 4.x has no true DAC. MQS is available on pins 10 and 12.'};
    fields(end+1, :) = {'PwmFrequencyHz', c.PwmFrequencyHz, 'numeric', ...
        'Higher frequencies filter to a smoother analog level.'};
    fields(end+1, :) = {'PwmResolutionBits', c.PwmResolutionBits, 'numeric', ...
        'Duty-cycle resolution.'};
end

fields(end+1, :) = {'Notes', char(c.Notes), 'text', 'Free text, such as the wiring colour.'};

nRows = size(fields, 1);
g = uigridlayout(obj.HChannels.InspectorPanel, [nRows + 1, 2]);
g.RowHeight = [repmat({26}, 1, nRows), {'1x'}];
g.ColumnWidth = {130, '1x'};
g.Padding = [6 6 6 6];
g.RowSpacing = 4;
g.Scrollable = 'on';

for r = 1:nRows
    name = fields{r, 1};
    value = fields{r, 2};
    kind = fields{r, 3};
    tip = fields{r, 4};

    lbl = uilabel(g, Text = name, HorizontalAlignment = 'right', Tooltip = tip);
    lbl.Layout.Row = r;
    lbl.Layout.Column = 1;

    if startsWith(kind, 'choice:')
        items = strsplit(extractAfter(kind, 'choice:'), '|');
        h = uidropdown(g, Items = items, Value = value, Tooltip = tip, ...
            ValueChangedFcn = @(src, ~) obj.onChannels('field', name, src.Value));
    elseif strcmp(kind, 'logical')
        h = uicheckbox(g, Text = '', Value = logical(value), Tooltip = tip, ...
            ValueChangedFcn = @(src, ~) obj.onChannels('field', name, src.Value));
    elseif strcmp(kind, 'numeric')
        h = uieditfield(g, 'numeric', Value = double(value), Tooltip = tip, ...
            ValueChangedFcn = @(src, ~) obj.onChannels('field', name, src.Value));
    else
        h = uieditfield(g, 'text', Value = value, Tooltip = tip, ...
            ValueChangedFcn = @(src, ~) obj.onChannels('field', name, src.Value));
    end

    h.Layout.Row = r;
    h.Layout.Column = 2;
end
end


function localRefreshPinPicker_(obj, c, idx)
% localRefreshPinPicker_(obj, c, idx)
% List the pins the board can use for this channel, marking those in use.
board = obj.Program.Board;

if c.Kind == "Analog" && c.Direction == "Input"
    capability = "analogIn";
elseif c.Kind == "Analog"
    capability = "pwm";
else
    capability = "digital";
end

used = containers.Map('KeyType', 'double', 'ValueType', 'char');
for k = 1:numel(obj.Program.Channels)
    if k == idx
        continue
    end
    other = obj.Program.Channels(k);
    if other.Pin >= 0
        used(other.Pin) = char(other.Name);
    end
end

items = {'(none)'};
for pin = 0:board.NumPins - 1
    if ~board.supports(capability, pin)
        continue
    end
    label = sprintf('%d', pin);
    if board.isReserved(pin)
        label = [label ' (reserved)'];
    end
    if isKey(used, pin)
        label = sprintf('%s (used by %s)', label, used(pin));
    end
    items{end+1} = label;
end

obj.HChannels.PinDrop.Items = items;

current = '(none)';
for k = 1:numel(items)
    if startsWith(items{k}, sprintf('%d', c.Pin)) && ...
            sscanf(items{k}, '%d') == c.Pin
        current = items{k};
        break
    end
end
obj.HChannels.PinDrop.Value = current;

obj.HChannels.PinNote.Text = char(board.describe());
end


% =========================================================================
function localRefreshStates_(obj)
% localRefreshStates_(obj)
% State list and inspector.
S = obj.Program.States;
n = numel(S);

items = cell(1, n);
for i = 1:n
    marker = '  ';
    if strcmp(S(i).Name, obj.Program.StartState)
        marker(1) = '>';
    end
    if S(i).IsTerminal
        marker(2) = '*';
    end
    items{i} = sprintf('%s %s', marker, S(i).Name);
end

obj.HStates.List.Items = items;
obj.HStates.List.ItemsData = 1:n;

idx = obj.SelectedState;
if idx >= 1 && idx <= n
    obj.HStates.List.Value = idx;
else
    idx = 0;
end

varItems = [{'literal'}, cellstr(localVarNames_(obj.Program))];
obj.HStates.DurationVar.Items = varItems;

if idx == 0
    obj.HStates.Name.Value = '';
    obj.HStates.Notes.Value = {''};
    obj.HStates.Duration.Value = 0;
    obj.HStates.DurationVar.Value = 'literal';
    obj.HStates.IsTerminal.Value = false;
    obj.HStates.RespCode.Text = '(none)';
    obj.HStates.ActionTable.Data = {};
    obj.HStates.TransTable.Data = {};
    obj.HStates.Hint.Text = 'Select a state, or add one.';
    return
end

s = S(idx);
obj.HStates.Name.Value = char(s.Name);
obj.HStates.Notes.Value = cellstr(string(s.Notes));
obj.HStates.IsTerminal.Value = s.IsTerminal;

[isRef, refName] = teensy.isVarRef(s.DurationMs);
if isRef
    obj.HStates.DurationVar.Value = char(refName);
    obj.HStates.Duration.Value = obj.Program.resolve(s.DurationMs);
    obj.HStates.Duration.Enable = 'off';
else
    obj.HStates.DurationVar.Value = 'literal';
    value = double(s.DurationMs);
    if ~isfinite(value)
        value = Inf;
    end
    obj.HStates.Duration.Value = value;
    obj.HStates.Duration.Enable = 'on';
end

if isempty(s.RespCodeBits)
    obj.HStates.RespCode.Text = '(none)';
else
    obj.HStates.RespCode.Text = char(strjoin(string(s.RespCodeBits), ' + '));
end

actionData = cell(numel(s.EntryActions) + numel(s.ExitActions), 2);
row = 0;
for i = 1:numel(s.EntryActions)
    row = row + 1;
    actionData(row, :) = {'entry', char(s.EntryActions(i).describe())};
end
for i = 1:numel(s.ExitActions)
    row = row + 1;
    actionData(row, :) = {'exit', char(s.ExitActions(i).describe())};
end
obj.HStates.ActionTable.Data = actionData;

transData = cell(numel(s.Transitions), 3);
for i = 1:numel(s.Transitions)
    t = s.Transitions(i);
    target = char(t.Target);
    if isempty(target)
        target = '(stay)';
    end
    transData(i, :) = {i, char(t.Condition.describe(obj.Program)), target};
end
obj.HStates.TransTable.Data = transData;

if numel(s.Transitions) > 1
    obj.HStates.Hint.Text = 'Transitions are tested top down; the first match wins.';
else
    obj.HStates.Hint.Text = '';
end
end


% =========================================================================
function localRefreshVariables_(obj)
% localRefreshVariables_(obj)
% Variable table, usage list and the hw.Parameter preview.
V = obj.Program.Variables;
n = numel(V);

data = cell(n, 8);
for i = 1:n
    data(i, :) = {char(V(i).Name), char(V(i).Type), V(i).Value, V(i).Min, V(i).Max, ...
        char(V(i).Units), V(i).UpdateEveryTrial, char(V(i).Description)};
end
obj.HVariables.Table.Data = data;

specs = obj.Program.parameterSpecs();
preview = cell(numel(specs), 6);
for i = 1:numel(specs)
    opts = specs(i).Options;
    access = 'Any';
    type = 'Float';
    if isfield(opts, 'Access'), access = opts.Access; end
    if isfield(opts, 'Type'), type = opts.Type; end
    preview(i, :) = {specs(i).Name, access, type, specs(i).Value, ...
        char(specs(i).Origin), char(specs(i).Description)};
end
obj.HVariables.Preview.Data = preview;

idx = obj.SelectedVariable;
if idx >= 1 && idx <= n
    usage = localFindUsage_(obj.Program, V(idx).Name);
    usageData = cell(numel(usage), 2);
    for i = 1:numel(usage)
        usageData(i, :) = {char(usage(i).State), char(usage(i).Where)};
    end
    obj.HVariables.Usage.Data = usageData;
else
    obj.HVariables.Usage.Data = {};
end
end


function usage = localFindUsage_(program, varName)
% usage = localFindUsage_(program, varName)
% Every place a variable is referenced, including inside condition trees.
usage = struct('State', {}, 'Where', {}, 'Index', {});
ref = teensy.varRef(varName);

for i = 1:numel(program.States)
    S = program.States(i);

    if isequal(string(S.DurationMs), ref)
        usage(end+1) = struct('State', S.Name, 'Where', "state duration", 'Index', i);
    end

    usage = localScanActions_(usage, S.EntryActions, S.Name, "entry action", i, varName);
    usage = localScanActions_(usage, S.ExitActions, S.Name, "exit action", i, varName);

    for k = 1:numel(S.Transitions)
        T = S.Transitions(k);
        if any(strcmp(T.Condition.varsUsed(), varName))
            usage(end+1) = struct('State', S.Name, ...
                'Where', sprintf("transition %d condition", k), 'Index', i);
        end
        usage = localScanActions_(usage, T.Actions, S.Name, ...
            sprintf("transition %d action", k), i, varName);
    end
end

for i = 1:numel(program.GlobalTimers)
    if isequal(string(program.GlobalTimers(i).DurationMs), ref)
        usage(end+1) = struct('State', "(timer)", ...
            'Where', sprintf("timer '%s' duration", program.GlobalTimers(i).Name), 'Index', 0);
    end
end
end


function usage = localScanActions_(usage, actions, stateName, label, stateIdx, varName)
% usage = localScanActions_(...)
% Record any action in the array that references the variable.
for i = 1:numel(actions)
    if any(strcmp(actions(i).varsUsed(), varName))
        usage(end+1) = struct('State', stateName, ...
            'Where', sprintf("%s %d", label, i), 'Index', stateIdx);
    end
end
end


% =========================================================================
function localRefreshSimulate_(obj)
% localRefreshSimulate_(obj)
% Rebuild the virtual box controls to match the channel set.
delete(obj.HSim.InputPanel.Children);

C = obj.Program.Channels;
inputs = C([C.Direction] == "Input");
outputs = C([C.Direction] == "Output");

nRows = numel(inputs) + numel(outputs) + 2;
g = uigridlayout(obj.HSim.InputPanel, [max(nRows, 1), 2]);
g.RowHeight = repmat({26}, 1, max(nRows, 1));
g.ColumnWidth = {110, '1x'};
g.Padding = [4 4 4 4];
g.RowSpacing = 3;
g.Scrollable = 'on';

obj.HSim.InputControls = struct();
obj.HSim.OutputLamps = struct();

row = 0;

if ~isempty(inputs)
    row = row + 1;
    h = uilabel(g, Text = 'Inputs', FontWeight = 'bold');
    h.Layout.Row = row;
    h.Layout.Column = [1 2];
end

for i = 1:numel(inputs)
    c = inputs(i);
    row = row + 1;
    field = matlab.lang.makeValidName(char(c.Name));

    lbl = uilabel(g, Text = char(c.Name), HorizontalAlignment = 'right');
    lbl.Layout.Row = row;
    lbl.Layout.Column = 1;

    if c.Kind == "Digital"
        h = uibutton(g, 'state', Text = 'press', ...
            Tooltip = sprintf('Drive %s high. Click again to release.', c.Name), ...
            ValueChangedFcn = @(src, ~) obj.onSimulate('input', c.Name, double(src.Value)));
    else
        h = uislider(g, ...
            Limits = [min(0, c.ThresholdLow - 1), max(c.ThresholdHigh * 2, c.ThresholdHigh + 1)], ...
            Value = 0, ...
            Tooltip = sprintf('%s in %s. Trips at %g and releases at %g.', ...
                c.Name, c.Units, c.ThresholdHigh, c.ThresholdLow), ...
            ValueChangedFcn = @(src, ~) obj.onSimulate('input', c.Name, src.Value));
    end

    h.Layout.Row = row;
    h.Layout.Column = 2;
    obj.HSim.InputControls.(field) = h;
end

if ~isempty(outputs)
    row = row + 1;
    h = uilabel(g, Text = 'Outputs', FontWeight = 'bold');
    h.Layout.Row = row;
    h.Layout.Column = [1 2];
end

for i = 1:numel(outputs)
    c = outputs(i);
    row = row + 1;
    field = matlab.lang.makeValidName(char(c.Name));

    lbl = uilabel(g, Text = char(c.Name), HorizontalAlignment = 'right');
    lbl.Layout.Row = row;
    lbl.Layout.Column = 1;

    lamp = uilabel(g, Text = '  OFF  ', BackgroundColor = [0.85 0.85 0.85], ...
        HorizontalAlignment = 'center', ...
        Tooltip = sprintf('Live state of output %s during the simulation.', c.Name));
    lamp.Layout.Row = row;
    lamp.Layout.Column = 2;
    obj.HSim.OutputLamps.(field) = lamp;
end
end


% =========================================================================
function localRefreshCompile_(obj)
% localRefreshCompile_(obj)
% Report table, wire text and capacity readout.
report = obj.CompileResult.Report;

data = cell(numel(report), 5);
for i = 1:numel(report)
    data(i, :) = {char(report(i).Severity), char(report(i).Category), ...
        char(report(i).Where), char(report(i).Message), char(report(i).Remedy)};
end
obj.HCompile.Report.Data = data;

removeStyle(obj.HCompile.Report);
for severity = ["error", "warning", "info"]
    rows = find(strcmp(data(:, 1), severity));
    if isempty(rows)
        continue
    end
    addStyle(obj.HCompile.Report, ...
        uistyle(BackgroundColor = obj.SEVERITY_COLORS.(severity)), 'row', rows);
end

if isempty(obj.CompileResult.Text)
    obj.HCompile.Wire.Value = {'Compile the program to see the records that would be sent.'};
else
    obj.HCompile.Wire.Value = obj.CompileResult.Lines(:);
end

stats = obj.CompileResult.Stats;
if isempty(stats)
    stats = teensy.Compiler().stats(obj.Program);
end

capData = cell(numel(stats), 3);
for i = 1:numel(stats)
    capData(i, :) = {char(stats(i).Resource), stats(i).Used, stats(i).Limit};
end
obj.HCompile.Capacity.Data = capData;

removeStyle(obj.HCompile.Capacity);
ratios = [stats.Used] ./ max([stats.Limit], 1);
overRows = find(ratios >= 1);
warnRows = find(ratios >= 0.8 & ratios < 1);
if ~isempty(overRows)
    addStyle(obj.HCompile.Capacity, ...
        uistyle(BackgroundColor = obj.SEVERITY_COLORS.error), 'row', overRows);
end
if ~isempty(warnRows)
    addStyle(obj.HCompile.Capacity, ...
        uistyle(BackgroundColor = obj.SEVERITY_COLORS.warning), 'row', warnRows);
end

canUpload = obj.CompileResult.Ok && ~isempty(obj.Interface) && ...
    isa(obj.Interface, 'hw.Teensy') && obj.Interface.IsConnected;
obj.HCompile.Upload.Enable = matlab.lang.OnOffSwitchState(canUpload);
end


% =========================================================================
function localRefreshChrome_(obj)
% localRefreshChrome_(obj)
% Window title, recent-files menu and the board readout.
obj.refreshTitle_();

if isempty(obj.Interface) || ~isa(obj.Interface, 'hw.Teensy')
    obj.HToolbar.Board.Text = 'No board bound';
elseif obj.Interface.IsConnected
    obj.HToolbar.Board.Text = sprintf('%s on %s', obj.Interface.BoardType, obj.Interface.Port);
else
    obj.HToolbar.Board.Text = sprintf('%s (not connected)', obj.Interface.Port);
end

recent = getappdata(0, obj.APPDATA_RECENT);
delete(obj.HMenu.Recent.Children);
if ~iscell(recent) || isempty(recent)
    m = uimenu(obj.HMenu.Recent, Text = '(None)');
    m.Enable = 'off';
else
    for i = 1:numel(recent)
        path = recent{i};
        uimenu(obj.HMenu.Recent, Text = path, ...
            MenuSelectedFcn = @(~, ~) obj.onOpenRecent(path));
    end
end
end


% =========================================================================
function names = localVarNames_(program)
% names = localVarNames_(program)
% Variable names as a string array.
if isempty(program.Variables)
    names = strings(1, 0);
else
    names = [program.Variables.Name];
end
end


function localSetEnable_(handles, names, state)
% localSetEnable_(handles, names, state)
% Set Enable on a list of named controls in a handle struct.
for i = 1:numel(names)
    h = handles.(names{i});
    if isgraphics(h) && isvalid(h)
        h.Enable = state;
    end
end
end
