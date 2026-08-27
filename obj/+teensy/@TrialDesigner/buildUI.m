function buildUI(obj, visible)
% buildUI(obj, visible)
% Create the figure, menus, toolbar, tabs and status bar.
%
% Called once from the constructor. Each tab's controls are stored in that
% tab's handle struct so a tab can be refreshed without touching the others.
%
% Parameters
%   visible - Show the window. Pass false for headless tests.
%
% See also: teensy.TrialDesigner, teensy.TrialDesigner.refreshAll

arguments
    obj
    visible (1,1) logical = true
end

obj.Figure = uifigure( ...
    Name = 'Teensy Trial Designer', ...
    Tag = obj.PREF_GROUP, ...
    Position = gui.fitPositionToMonitor(getpref(obj.PREF_GROUP, 'Position', [70 60 1480 940])), ...
    Color = obj.COLOR_FIG, ...
    Visible = matlab.lang.OnOffSwitchState(visible), ...
    CloseRequestFcn = @(~, ~) obj.onCloseRequest(), ...
    WindowKeyPressFcn = @(~, evt) obj.onFigureKeyPress(evt));

obj.Figure.UserData = obj;

localBuildMenus_(obj);

outer = uigridlayout(obj.Figure, [3 1]);
outer.RowHeight = {34, '1x', 26};
outer.ColumnWidth = {'1x'};
outer.RowSpacing = 6;
outer.Padding = [8 8 8 8];

localBuildToolbar_(obj, outer);

obj.TabGroup = uitabgroup(outer);
obj.TabGroup.Layout.Row = 2;
obj.TabGroup.Layout.Column = 1;
obj.TabGroup.SelectionChangedFcn = @(~, evt) obj.onTabChanged(evt);

obj.HChannels.Tab = uitab(obj.TabGroup, Title = 'Channels');
obj.HStates.Tab = uitab(obj.TabGroup, Title = 'States');
obj.HVariables.Tab = uitab(obj.TabGroup, Title = 'Variables');
obj.HSim.Tab = uitab(obj.TabGroup, Title = 'Test Bench');
obj.HCompile.Tab = uitab(obj.TabGroup, Title = 'Compile & Upload');

% gui.components.StatusBar must be given an explicit Position: with it empty the
% constructor reads parent.Position(3), and a uigridlayout has no Position.
% The value is ignored once Layout.Row is set.
obj.StatusBar = gui.components.StatusBar(outer, ...
    Position = [1 1 400 24], ...
    InitialText = 'Loading Trial Designer...');
obj.StatusBar.Label.Layout.Row = 3;
obj.StatusBar.Label.Layout.Column = 1;

localBuildChannelsTab_(obj);
localBuildStatesTab_(obj);
localBuildVariablesTab_(obj);
localBuildSimulateTab_(obj);
localBuildCompileTab_(obj);

obj.refreshUndoMenu_();
end


% =========================================================================
function localBuildMenus_(obj)
% localBuildMenus_(obj)
% Build the menu bar. Shift combinations carry their hint in the label,
% because uimenu Accelerator only supports plain Ctrl combinations.
fileMenu = uimenu(obj.Figure, Text = 'File');
uimenu(fileMenu, Text = 'New', Accelerator = 'N', ...
    MenuSelectedFcn = @(~, ~) obj.onNew());
uimenu(fileMenu, Text = 'New From Template...', ...
    MenuSelectedFcn = @(~, ~) obj.onNewFromTemplate());
uimenu(fileMenu, Text = 'Open...', Accelerator = 'O', Separator = 'on', ...
    MenuSelectedFcn = @(~, ~) obj.onOpen());
obj.HMenu.Recent = uimenu(fileMenu, Text = 'Open Recent');
uimenu(fileMenu, Text = 'Save', Accelerator = 'S', Separator = 'on', ...
    MenuSelectedFcn = @(~, ~) obj.onSave());
uimenu(fileMenu, Text = 'Save As... (Ctrl+Shift+S)', ...
    MenuSelectedFcn = @(~, ~) obj.onSaveAs());
uimenu(fileMenu, Text = 'Edit Info...', Accelerator = 'I', Separator = 'on', ...
    MenuSelectedFcn = @(~, ~) obj.onEditInfo());
uimenu(fileMenu, Text = 'Export Program to Workspace', ...
    MenuSelectedFcn = @(~, ~) obj.onCompile('workspace'));

editMenu = uimenu(obj.Figure, Text = 'Edit');
obj.HMenu.Undo = uimenu(editMenu, Text = 'Undo', Accelerator = 'Z', ...
    MenuSelectedFcn = @(~, ~) obj.onUndo());
obj.HMenu.Redo = uimenu(editMenu, Text = 'Redo', Accelerator = 'Y', ...
    MenuSelectedFcn = @(~, ~) obj.onRedo());

insertMenu = uimenu(obj.Figure, Text = 'Insert');
uimenu(insertMenu, Text = 'State', MenuSelectedFcn = @(~, ~) obj.onStates('add'));
uimenu(insertMenu, Text = 'Digital Input', ...
    MenuSelectedFcn = @(~, ~) obj.onChannels('add', "Input", "Digital"));
uimenu(insertMenu, Text = 'Digital Output', ...
    MenuSelectedFcn = @(~, ~) obj.onChannels('add', "Output", "Digital"));
uimenu(insertMenu, Text = 'Analog Input', ...
    MenuSelectedFcn = @(~, ~) obj.onChannels('add', "Input", "Analog"));
uimenu(insertMenu, Text = 'Analog Output', ...
    MenuSelectedFcn = @(~, ~) obj.onChannels('add', "Output", "Analog"));
uimenu(insertMenu, Text = 'Variable', Separator = 'on', ...
    MenuSelectedFcn = @(~, ~) obj.onVariables('add'));
uimenu(insertMenu, Text = 'Global Timer', MenuSelectedFcn = @(~, ~) obj.onVariables('addTimer'));
uimenu(insertMenu, Text = 'Counter', MenuSelectedFcn = @(~, ~) obj.onVariables('addCounter'));

programMenu = uimenu(obj.Figure, Text = 'Program');
uimenu(programMenu, Text = 'Validate', MenuSelectedFcn = @(~, ~) obj.onCompile('validate'));
uimenu(programMenu, Text = 'Compile', MenuSelectedFcn = @(~, ~) obj.onCompile('compile'));
uimenu(programMenu, Text = 'Upload to Board', Separator = 'on', ...
    MenuSelectedFcn = @(~, ~) obj.onCompile('upload'));
uimenu(programMenu, Text = 'Insert Into Protocol...', ...
    MenuSelectedFcn = @(~, ~) obj.onCompile('insert'));

viewMenu = uimenu(obj.Figure, Text = 'View');
uimenu(viewMenu, Text = 'Auto Layout Diagram', ...
    MenuSelectedFcn = @(~, ~) obj.onStates('autolayout'));
obj.HMenu.SnapToGrid = uimenu(viewMenu, Text = 'Snap to Grid', Checked = 'on', ...
    MenuSelectedFcn = @(src, ~) obj.onStates('snap', src));

helpMenu = uimenu(obj.Figure, Text = 'Help');
uimenu(helpMenu, Text = 'User Guide', ...
    MenuSelectedFcn = @(~, ~) obj.onOpenDocumentation('guide'));
uimenu(helpMenu, Text = 'Wire Protocol Reference', ...
    MenuSelectedFcn = @(~, ~) obj.onOpenDocumentation('protocol'));
end


% =========================================================================
function localBuildToolbar_(obj, outer)
% localBuildToolbar_(obj, outer)
% Build the toolbar row of the outer grid.
bar = uigridlayout(outer, [1 9]);
bar.Layout.Row = 1;
bar.Layout.Column = 1;
bar.ColumnWidth = {90, 130, 70, 90, 90, 100, '1x', 220};
bar.RowHeight = {'1x'};
bar.Padding = [0 0 0 0];
bar.ColumnSpacing = 6;

localButton_(bar, 'New', 'Start a new program.', @(~, ~) obj.onNew());
localButton_(bar, 'Template...', 'Start from a working paradigm.', ...
    @(~, ~) obj.onNewFromTemplate());
localButton_(bar, 'Open', 'Open a .etsm program file.', @(~, ~) obj.onOpen());
localButton_(bar, 'Save', 'Save the program.', @(~, ~) obj.onSave());

b = localButton_(bar, 'Validate', ...
    ['Check the program for problems without compiling it.' newline ...
     'Results appear on the Compile & Upload tab.'], @(~, ~) obj.onCompile('validate'));
b.FontWeight = 'bold';

b = localButton_(bar, 'Compile', ...
    ['Validate, then emit the wire program the board runs.' newline ...
     'Refuses to emit while any error remains.'], @(~, ~) obj.onCompile('compile'));
b.BackgroundColor = obj.COLOR_PRIMARY;
b.FontColor = 'w';
b.FontWeight = 'bold';

obj.HToolbar.Board = uilabel(bar, ...
    Text = '', ...
    HorizontalAlignment = 'right', ...
    FontAngle = 'italic', ...
    FontColor = obj.COLOR_HINT);
obj.HToolbar.Board.Layout.Column = 8;
end


% =========================================================================
function localBuildChannelsTab_(obj)
% localBuildChannelsTab_(obj)
% Channel table on the left, an inspector for the selected channel on the right.
g = uigridlayout(obj.HChannels.Tab, [1 2]);
g.ColumnWidth = {'2x', 380};
g.RowHeight = {'1x'};
g.Padding = [8 8 8 8];

left = uigridlayout(g, [2 1]);
left.Layout.Row = 1;
left.Layout.Column = 1;
left.RowHeight = {'1x', 34};
left.Padding = [0 0 0 0];

obj.HChannels.Table = uitable(left, ...
    ColumnName = {'Name', 'Direction', 'Kind', 'Pin', 'Active High', ...
        'Debounce (ms)', 'Thresh Hi', 'Thresh Lo', 'Idle', 'Units', 'Notes'}, ...
    ColumnEditable = [true false false true true true true true true true true], ...
    ColumnFormat = {'char', 'char', 'char', 'numeric', 'logical', ...
        'numeric', 'numeric', 'numeric', 'numeric', 'char', 'char'}, ...
    ColumnWidth = {110, 76, 66, 50, 80, 92, 76, 76, 46, 56, 'auto'}, ...
    BackgroundColor = [1 1 1; 0.979 0.984 0.992], ...
    Tooltip = ['One row per logical input or output.' newline ...
               'Direction and Kind are set when the channel is created; ' ...
               'delete and re-add to change them.'], ...
    CellEditCallback = @(~, evt) obj.onChannels('edited', evt), ...
    CellSelectionCallback = @(~, evt) obj.onChannels('selected', evt));
obj.HChannels.Table.Layout.Row = 1;

buttons = uigridlayout(left, [1 7]);
buttons.Layout.Row = 2;
buttons.ColumnWidth = {'1x', '1x', '1x', '1x', '1x', '1x', '1x'};
buttons.Padding = [0 0 0 0];
buttons.ColumnSpacing = 4;

obj.HChannels.AddDigIn = localButton_(buttons, '+ Digital In', ...
    'Add a debounced digital input, such as a nose poke or lick spout.', ...
    @(~, ~) obj.onChannels('add', "Input", "Digital"));
obj.HChannels.AddDigOut = localButton_(buttons, '+ Digital Out', ...
    'Add a digital output, such as a reward valve or a cue light.', ...
    @(~, ~) obj.onChannels('add', "Output", "Digital"));
obj.HChannels.AddAnaIn = localButton_(buttons, '+ Analog In', ...
    'Add a thresholded analog input, such as a piezo or a force sensor.', ...
    @(~, ~) obj.onChannels('add', "Input", "Analog"));
obj.HChannels.AddAnaOut = localButton_(buttons, '+ Analog Out', ...
    ['Add an analog output. Teensy 4.x has no true DAC, so this is PWM,' newline ...
     'MQS on pins 10 and 12, or an external SPI DAC.'], ...
    @(~, ~) obj.onChannels('add', "Output", "Analog"));
obj.HChannels.Duplicate = localButton_(buttons, 'Duplicate', ...
    'Copy the selected channel onto the next free pin.', ...
    @(~, ~) obj.onChannels('duplicate'));
obj.HChannels.Remove = localButton_(buttons, 'Remove', ...
    'Delete the selected channel. References to it become validation errors.', ...
    @(~, ~) obj.onChannels('remove'));
obj.HChannels.Defaults = localButton_(buttons, 'Default Set', ...
    'Replace the channels with a standard operant box layout.', ...
    @(~, ~) obj.onChannels('defaults'));

right = uigridlayout(g, [3 1]);
right.Layout.Row = 1;
right.Layout.Column = 2;
right.RowHeight = {'1x', 'fit', 'fit'};
right.Padding = [0 0 0 0];

obj.HChannels.InspectorPanel = uipanel(right, Title = 'Channel', ...
    BackgroundColor = obj.COLOR_PANEL, ForegroundColor = [0.22 0.30 0.40], ...
    FontWeight = 'bold');
obj.HChannels.InspectorPanel.Layout.Row = 1;

obj.HChannels.PinPanel = uipanel(right, Title = 'Pin', ...
    BackgroundColor = obj.COLOR_PANEL, ForegroundColor = [0.22 0.30 0.40], ...
    FontWeight = 'bold');
obj.HChannels.PinPanel.Layout.Row = 2;

pinGrid = uigridlayout(obj.HChannels.PinPanel, [2 2]);
pinGrid.RowHeight = {26, 'fit'};
pinGrid.ColumnWidth = {70, '1x'};

lbl = uilabel(pinGrid, Text = 'Pin');
lbl.Layout.Row = 1;
lbl.Layout.Column = 1;

obj.HChannels.PinDrop = uidropdown(pinGrid, ...
    Items = {'(none)'}, ...
    Tooltip = ['Only pins the board can use for this channel kind are listed.' newline ...
               'Pins already claimed by another channel are marked.'], ...
    ValueChangedFcn = @(src, ~) obj.onChannels('pin', src.Value));
obj.HChannels.PinDrop.Layout.Row = 1;
obj.HChannels.PinDrop.Layout.Column = 2;

obj.HChannels.PinNote = uilabel(pinGrid, Text = '', ...
    WordWrap = 'on', FontAngle = 'italic', FontColor = obj.COLOR_HINT);
obj.HChannels.PinNote.Layout.Row = 2;
obj.HChannels.PinNote.Layout.Column = [1 2];

obj.HChannels.LivePanel = uipanel(right, Title = 'Live I/O', ...
    BackgroundColor = obj.COLOR_PANEL, ForegroundColor = [0.22 0.30 0.40], ...
    FontWeight = 'bold');
obj.HChannels.LivePanel.Layout.Row = 3;

liveGrid = uigridlayout(obj.HChannels.LivePanel, [1 3]);
liveGrid.RowHeight = {28};
liveGrid.ColumnWidth = {'1x', '1x', '1x'};

obj.HChannels.LivePulse = localButton_(liveGrid, 'Pulse', ...
    'Fire a 50 ms pulse on the selected output. Requires a connected board.', ...
    @(~, ~) obj.onChannels('livePulse'));
obj.HChannels.LiveOn = localButton_(liveGrid, 'On', ...
    'Drive the selected output high. Requires a connected board.', ...
    @(~, ~) obj.onChannels('liveOn'));
obj.HChannels.LiveOff = localButton_(liveGrid, 'Off', ...
    'Drive the selected output low. Requires a connected board.', ...
    @(~, ~) obj.onChannels('liveOff'));
end


% =========================================================================
function localBuildStatesTab_(obj)
% localBuildStatesTab_(obj)
% State list, diagram canvas and inspector.
g = uigridlayout(obj.HStates.Tab, [1 3]);
g.ColumnWidth = {190, '1x', 400};
g.RowHeight = {'1x'};
g.Padding = [8 8 8 8];

% --- Left: the state list ---
left = uigridlayout(g, [2 1]);
left.Layout.Column = 1;
left.RowHeight = {'1x', 128};
left.Padding = [0 0 0 0];

obj.HStates.List = uilistbox(left, ...
    Items = {}, ...
    Tooltip = ['States in the program.' newline ...
               '>  marks the start state, *  marks a terminal state.'], ...
    ValueChangedFcn = @(src, ~) obj.onStates('selected', src));
obj.HStates.List.Layout.Row = 1;

listButtons = uigridlayout(left, [4 2]);
listButtons.Layout.Row = 2;
listButtons.RowHeight = {28, 28, 28, 28};
listButtons.ColumnWidth = {'1x', '1x'};
listButtons.Padding = [0 0 0 0];
listButtons.RowSpacing = 3;
listButtons.ColumnSpacing = 3;

obj.HStates.Add = localButton_(listButtons, 'Add', 'Add a state.', ...
    @(~, ~) obj.onStates('add'));
obj.HStates.Duplicate = localButton_(listButtons, 'Duplicate', ...
    'Copy the selected state, its actions and its transitions.', ...
    @(~, ~) obj.onStates('duplicate'));
obj.HStates.Rename = localButton_(listButtons, 'Rename', ...
    'Rename the state. Every transition targeting it is rewritten.', ...
    @(~, ~) obj.onStates('rename'));
obj.HStates.Remove = localButton_(listButtons, 'Remove', ...
    'Delete the state.', @(~, ~) obj.onStates('remove'));
obj.HStates.SetStart = localButton_(listButtons, 'Set as Start', ...
    'Trials begin in this state.', @(~, ~) obj.onStates('setstart'));
obj.HStates.Terminal = localButton_(listButtons, 'Toggle End', ...
    ['Mark or unmark the state as terminal.' newline ...
     'Entering a terminal state latches the response code and ends the trial.'], ...
    @(~, ~) obj.onStates('terminal'));
obj.HStates.MoveUp = localButton_(listButtons, 'Move Up', ...
    'Reorder the list. Presentation only.', @(~, ~) obj.onStates('up'));
obj.HStates.MoveDown = localButton_(listButtons, 'Move Down', ...
    'Reorder the list. Presentation only.', @(~, ~) obj.onStates('down'));

% --- Center: the diagram ---
center = uipanel(g, Title = 'Diagram', BackgroundColor = [1 1 1], ...
    ForegroundColor = [0.22 0.30 0.40], FontWeight = 'bold');
center.Layout.Column = 2;

centerGrid = uigridlayout(center, [1 1]);
centerGrid.Padding = [2 2 2 2];

ax = uiaxes(centerGrid);
ax.XLim = [-0.06 1.06];
ax.YLim = [-0.10 1.10];
ax.XTick = [];
ax.YTick = [];
ax.Box = 'off';
ax.XColor = 'none';
ax.YColor = 'none';
ax.Toolbar.Visible = 'off';
ax.Interactions = [];
ax.PickableParts = 'all';
ax.ButtonDownFcn = @(~, evt) obj.onDiagram('down', evt);
hold(ax, 'on');

obj.HStates.Axes = ax;
obj.HStates.NodeMap = struct('Index', {}, 'X', {}, 'Y', {}, 'W', {}, 'H', {});
obj.HStates.LiveState = 0;
obj.HStates.Snap = true;

% --- Right: the inspector ---
right = uipanel(g, Title = 'State', BackgroundColor = obj.COLOR_PANEL, ...
    ForegroundColor = [0.22 0.30 0.40], FontWeight = 'bold');
right.Layout.Column = 3;

r = uigridlayout(right, [10 3]);
r.RowHeight = {26, 46, 26, 26, 26, '1x', 30, '1x', 30, 20};
r.ColumnWidth = {92, '1x', 74};
r.Scrollable = 'on';
r.Padding = [6 6 6 6];
r.RowSpacing = 4;

localLabel_(r, 'Name', 1);
obj.HStates.Name = uieditfield(r, 'text', ...
    Tooltip = 'State name. Renaming rewrites every transition that targets it.', ...
    ValueChangedFcn = @(src, ~) obj.onStates('field', 'Name', src.Value));
obj.HStates.Name.Layout.Row = 1;
obj.HStates.Name.Layout.Column = [2 3];

localLabel_(r, 'Notes', 2);
obj.HStates.Notes = uitextarea(r, ...
    Tooltip = 'What this state is for. Shown as the node tooltip on the diagram.', ...
    ValueChangedFcn = @(src, ~) obj.onStates('field', 'Notes', src.Value));
obj.HStates.Notes.Layout.Row = 2;
obj.HStates.Notes.Layout.Column = [2 3];

localLabel_(r, 'Duration (ms)', 3);
obj.HStates.Duration = uieditfield(r, 'numeric', ...
    Tooltip = ['How long the state timer runs. Leave it at Inf for a state' newline ...
               'that only leaves on an input.'], ...
    ValueChangedFcn = @(src, ~) obj.onStates('field', 'DurationMs', src.Value));
obj.HStates.Duration.Layout.Row = 3;
obj.HStates.Duration.Layout.Column = 2;

obj.HStates.DurationVar = uidropdown(r, ...
    Items = {'literal'}, ...
    Tooltip = ['Drive the duration from a variable instead of a fixed number,' newline ...
               'so a protocol can vary it per trial.'], ...
    ValueChangedFcn = @(src, ~) obj.onStates('durationVar', src.Value));
obj.HStates.DurationVar.Layout.Row = 3;
obj.HStates.DurationVar.Layout.Column = 3;

localLabel_(r, 'Ends trial', 4);
obj.HStates.IsTerminal = uicheckbox(r, Text = 'terminal state', ...
    Tooltip = ['Entering this state latches RespCode and RespLatency and raises' newline ...
               'TrialComplete, which is what tells the runtime the trial is over.'], ...
    ValueChangedFcn = @(src, ~) obj.onStates('field', 'IsTerminal', src.Value));
obj.HStates.IsTerminal.Layout.Row = 4;
obj.HStates.IsTerminal.Layout.Column = [2 3];

localLabel_(r, 'Response', 5);
obj.HStates.RespCode = uilabel(r, Text = '(none)', ...
    Tooltip = 'Response-code bits added when this state is entered.');
obj.HStates.RespCode.Layout.Row = 5;
obj.HStates.RespCode.Layout.Column = 2;

obj.HStates.EditResp = localButton_(r, 'Edit...', ...
    'Pick the epsych.BitMask outcome bits for this state.', ...
    @(~, ~) obj.onStates('respcode'));
obj.HStates.EditResp.Layout.Row = 5;
obj.HStates.EditResp.Layout.Column = 3;

obj.HStates.ActionTable = uitable(r, ...
    ColumnName = {'When', 'Action'}, ...
    ColumnEditable = [false false], ...
    ColumnWidth = {56, 'auto'}, ...
    Tooltip = 'Actions run when the state is entered or left, in order.', ...
    CellSelectionCallback = @(~, evt) obj.onStates('actionSelected', evt));
obj.HStates.ActionTable.Layout.Row = 6;
obj.HStates.ActionTable.Layout.Column = [1 3];

actionButtons = uigridlayout(r, [1 4]);
actionButtons.Layout.Row = 7;
actionButtons.Layout.Column = [1 3];
actionButtons.ColumnWidth = {'1x', '1x', '1x', '1x'};
actionButtons.Padding = [0 0 0 0];
actionButtons.ColumnSpacing = 3;

obj.HStates.AddEntry = localButton_(actionButtons, '+ Entry', ...
    'Add an action that runs when the state is entered.', ...
    @(~, ~) obj.onStates('addAction', 'entry'));
obj.HStates.AddExit = localButton_(actionButtons, '+ Exit', ...
    'Add an action that runs when the state is left.', ...
    @(~, ~) obj.onStates('addAction', 'exit'));
obj.HStates.EditAction = localButton_(actionButtons, 'Edit', ...
    'Edit the selected action.', @(~, ~) obj.onStates('editAction'));
obj.HStates.RemoveAction = localButton_(actionButtons, 'Remove', ...
    'Delete the selected action.', @(~, ~) obj.onStates('removeAction'));

obj.HStates.TransTable = uitable(r, ...
    ColumnName = {'#', 'When', 'Go to'}, ...
    ColumnEditable = [false false false], ...
    ColumnWidth = {26, 'auto', 92}, ...
    Tooltip = ['Transitions are tested in order and the FIRST match wins,' newline ...
               'so the order of this list is part of the paradigm.'], ...
    CellSelectionCallback = @(~, evt) obj.onStates('transSelected', evt));
obj.HStates.TransTable.Layout.Row = 8;
obj.HStates.TransTable.Layout.Column = [1 3];

transButtons = uigridlayout(r, [1 5]);
transButtons.Layout.Row = 9;
transButtons.Layout.Column = [1 3];
transButtons.ColumnWidth = {'1x', '1x', '1x', 34, 34};
transButtons.Padding = [0 0 0 0];
transButtons.ColumnSpacing = 3;

obj.HStates.AddTrans = localButton_(transButtons, '+ Add', ...
    'Add a transition out of this state.', @(~, ~) obj.onStates('addTrans'));
obj.HStates.EditTrans = localButton_(transButtons, 'Edit', ...
    'Edit the selected transition''s condition, target and actions.', ...
    @(~, ~) obj.onStates('editTrans'));
obj.HStates.RemoveTrans = localButton_(transButtons, 'Remove', ...
    'Delete the selected transition.', @(~, ~) obj.onStates('removeTrans'));
obj.HStates.TransUp = localButton_(transButtons, '^', ...
    'Test this transition earlier. Order decides which of two simultaneous matches wins.', ...
    @(~, ~) obj.onStates('transUp'));
obj.HStates.TransDown = localButton_(transButtons, 'v', ...
    'Test this transition later.', @(~, ~) obj.onStates('transDown'));

obj.HStates.Hint = uilabel(r, Text = '', FontAngle = 'italic', ...
    FontColor = obj.COLOR_HINT);
obj.HStates.Hint.Layout.Row = 10;
obj.HStates.Hint.Layout.Column = [1 3];
end


% =========================================================================
function localBuildVariablesTab_(obj)
% localBuildVariablesTab_(obj)
% Variables, the parameters they become, and where each is used.
g = uigridlayout(obj.HVariables.Tab, [3 2]);
g.RowHeight = {'1x', 34, '1x'};
g.ColumnWidth = {'1.4x', '1x'};
g.Padding = [8 8 8 8];

obj.HVariables.Table = uitable(g, ...
    ColumnName = {'Name', 'Type', 'Default', 'Min', 'Max', 'Units', ...
        'Per Trial', 'Description'}, ...
    ColumnEditable = [true true true true true true true true], ...
    ColumnFormat = {'char', {'Float', 'Integer', 'Boolean'}, 'numeric', ...
        'numeric', 'numeric', 'char', 'logical', 'char'}, ...
    ColumnWidth = {130, 74, 76, 66, 76, 60, 74, 'auto'}, ...
    BackgroundColor = [1 1 1; 0.979 0.984 0.992], ...
    Tooltip = ['Named quantities the paradigm reads instead of fixed numbers.' newline ...
               'Per Trial variables become trial-table columns in the Protocol Designer.'], ...
    CellEditCallback = @(~, evt) obj.onVariables('edited', evt), ...
    CellSelectionCallback = @(~, evt) obj.onVariables('selected', evt));
obj.HVariables.Table.Layout.Row = 1;
obj.HVariables.Table.Layout.Column = 1;

usage = uipanel(g, Title = 'Where the selected variable is used', ...
    BackgroundColor = obj.COLOR_PANEL, ForegroundColor = [0.22 0.30 0.40], ...
    FontWeight = 'bold');
usage.Layout.Row = 1;
usage.Layout.Column = 2;

usageGrid = uigridlayout(usage, [1 1]);
usageGrid.Padding = [4 4 4 4];

obj.HVariables.Usage = uitable(usageGrid, ...
    ColumnName = {'State', 'Where'}, ...
    ColumnWidth = {100, 'auto'}, ...
    Tooltip = 'Double-click a row to jump to that state.', ...
    CellSelectionCallback = @(~, evt) obj.onVariables('usageSelected', evt));

buttons = uigridlayout(g, [1 5]);
buttons.Layout.Row = 2;
buttons.Layout.Column = [1 2];
buttons.ColumnWidth = {130, 130, 130, 150, '1x'};
buttons.Padding = [0 0 0 0];
buttons.ColumnSpacing = 5;

obj.HVariables.Add = localButton_(buttons, 'Add Variable', ...
    'Add a named quantity the paradigm can read.', @(~, ~) obj.onVariables('add'));
obj.HVariables.Remove = localButton_(buttons, 'Remove', ...
    'Delete the selected variable. References to it become validation errors.', ...
    @(~, ~) obj.onVariables('remove'));
obj.HVariables.AddTimer = localButton_(buttons, 'Add Timer', ...
    'Add a global timer, which runs independently of the state timer.', ...
    @(~, ~) obj.onVariables('addTimer'));
obj.HVariables.AddCounter = localButton_(buttons, 'Add Counter', ...
    'Add a counter that tallies edges on an input channel.', ...
    @(~, ~) obj.onVariables('addCounter'));

preview = uipanel(g, Title = 'Parameters this program will add to the protocol', ...
    BackgroundColor = obj.COLOR_PANEL, ForegroundColor = [0.22 0.30 0.40], ...
    FontWeight = 'bold');
preview.Layout.Row = 3;
preview.Layout.Column = [1 2];

previewGrid = uigridlayout(preview, [1 1]);
previewGrid.Padding = [4 4 4 4];

obj.HVariables.Preview = uitable(previewGrid, ...
    ColumnName = {'Parameter', 'Access', 'Type', 'Default', 'Origin', 'Description'}, ...
    ColumnWidth = {150, 62, 72, 70, 78, 'auto'}, ...
    Tooltip = ['These hw.Parameter objects are created on the Teensy interface' newline ...
               'when the program is inserted into a protocol.']);
end


% =========================================================================
function localBuildSimulateTab_(obj)
% localBuildSimulateTab_(obj)
% Virtual box on the left, timeline and results on the right.
g = uigridlayout(obj.HSim.Tab, [2 2]);
g.ColumnWidth = {300, '1x'};
g.RowHeight = {'1x', 200};
g.Padding = [8 8 8 8];

boxPanel = uipanel(g, Title = 'Virtual Box', BackgroundColor = obj.COLOR_PANEL, ...
    ForegroundColor = [0.22 0.30 0.40], FontWeight = 'bold');
boxPanel.Layout.Row = [1 2];
boxPanel.Layout.Column = 1;

boxGrid = uigridlayout(boxPanel, [3 1]);
boxGrid.RowHeight = {112, '1x', 'fit'};
boxGrid.Padding = [6 6 6 6];

controls = uigridlayout(boxGrid, [3 3]);
controls.Layout.Row = 1;
controls.RowHeight = {30, 30, 26};
controls.ColumnWidth = {'1x', '1x', '1x'};
controls.Padding = [0 0 0 0];
controls.RowSpacing = 3;

obj.HSim.Start = localButton_(controls, 'Start', ...
    'Start a trial from the program''s start state.', @(~, ~) obj.onSimulate('start'));
obj.HSim.Start.BackgroundColor = [0.20 0.75 0.20];
obj.HSim.Start.FontColor = 'w';
obj.HSim.Start.FontWeight = 'bold';

obj.HSim.Pause = localButton_(controls, 'Pause', 'Pause the running trial.', ...
    @(~, ~) obj.onSimulate('pause'));
obj.HSim.Pause.BackgroundColor = [1.00 0.80 0.20];

obj.HSim.Reset = localButton_(controls, 'Reset', 'Clear the trial and the timeline.', ...
    @(~, ~) obj.onSimulate('reset'));
obj.HSim.Reset.BackgroundColor = [0.85 0.25 0.25];
obj.HSim.Reset.FontColor = 'w';

obj.HSim.Step = localButton_(controls, 'Step 10 ms', ...
    'Advance the machine by 10 ms, for stepping through a contingency.', ...
    @(~, ~) obj.onSimulate('step'));

obj.HSim.SpeedLabel = uilabel(controls, Text = 'Speed', ...
    HorizontalAlignment = 'right');

obj.HSim.Speed = uidropdown(controls, ...
    Items = {'1x', '5x', '20x', 'as fast as possible'}, ...
    Value = '5x', ...
    Tooltip = 'How fast simulated time advances relative to the wall clock.', ...
    ValueChangedFcn = @(src, ~) obj.onSimulate('speed', src.Value));

obj.HSim.Clock = uilabel(controls, Text = 't = 0 ms', FontWeight = 'bold');
obj.HSim.Clock.Layout.Row = 3;
obj.HSim.Clock.Layout.Column = [1 2];

obj.HSim.StateLabel = uilabel(controls, Text = '', FontAngle = 'italic', ...
    FontColor = obj.COLOR_HINT);
obj.HSim.StateLabel.Layout.Row = 3;
obj.HSim.StateLabel.Layout.Column = 3;

obj.HSim.InputPanel = uipanel(boxGrid, Title = 'Inputs and outputs', ...
    BorderType = 'none', BackgroundColor = obj.COLOR_PANEL);
obj.HSim.InputPanel.Layout.Row = 2;

mc = uigridlayout(boxGrid, [4 2]);
mc.Layout.Row = 3;
mc.RowHeight = {24, 26, 26, 30};
mc.ColumnWidth = {96, '1x'};
mc.Padding = [0 6 0 0];
mc.RowSpacing = 3;

mcTitle = uilabel(mc, Text = 'Monte Carlo', FontWeight = 'bold');
mcTitle.Layout.Row = 1;
mcTitle.Layout.Column = [1 2];

localLabel_(mc, 'Subject', 2);
obj.HSim.Responder = uidropdown(mc, ...
    Items = {'perfect', 'guessing', 'impulsive', 'sluggish', 'biased'}, ...
    Value = 'guessing', ...
    Tooltip = ['A stochastic simulated subject. Running many trials against one' newline ...
               'shows whether the paradigm can actually produce every outcome.']);
obj.HSim.Responder.Layout.Row = 2;
obj.HSim.Responder.Layout.Column = 2;

localLabel_(mc, 'Trials', 3);
obj.HSim.NTrials = uispinner(mc, Value = 100, Limits = [1 5000], Step = 10, ...
    Tooltip = 'How many trials to simulate.');
obj.HSim.NTrials.Layout.Row = 3;
obj.HSim.NTrials.Layout.Column = 2;

obj.HSim.RunMC = localButton_(mc, 'Run Monte Carlo', ...
    'Simulate many trials and summarize the outcomes.', ...
    @(~, ~) obj.onSimulate('montecarlo'));
obj.HSim.RunMC.Layout.Row = 4;
obj.HSim.RunMC.Layout.Column = [1 2];
obj.HSim.RunMC.FontWeight = 'bold';

timelinePanel = uipanel(g, Title = 'Timeline', BackgroundColor = [1 1 1], ...
    ForegroundColor = [0.22 0.30 0.40], FontWeight = 'bold');
timelinePanel.Layout.Row = 1;
timelinePanel.Layout.Column = 2;

tlGrid = uigridlayout(timelinePanel, [1 1]);
tlGrid.Padding = [2 2 2 2];

obj.HSim.Axes = uiaxes(tlGrid);
obj.HSim.Axes.XLabel.String = 'time (ms)';
obj.HSim.Axes.YTick = [];
obj.HSim.Axes.Toolbar.Visible = 'off';
hold(obj.HSim.Axes, 'on');

resultPanel = uipanel(g, Title = 'Outcome', BackgroundColor = obj.COLOR_PANEL, ...
    ForegroundColor = [0.22 0.30 0.40], FontWeight = 'bold');
resultPanel.Layout.Row = 2;
resultPanel.Layout.Column = 2;

resGrid = uigridlayout(resultPanel, [1 2]);
resGrid.ColumnWidth = {'1x', '1.2x'};
resGrid.Padding = [6 6 6 6];

obj.HSim.Result = uitextarea(resGrid, Editable = 'off', ...
    FontName = 'Consolas', Value = {'No trial has been run yet.'});

obj.HSim.MCTable = uitable(resGrid, ...
    ColumnName = {'Measure', 'Value'}, ...
    ColumnWidth = {160, 'auto'}, ...
    Tooltip = 'Summary of the last Monte Carlo run.');
end


% =========================================================================
function localBuildCompileTab_(obj)
% localBuildCompileTab_(obj)
% Validation report, wire program preview, capacity, and the upload actions.
g = uigridlayout(obj.HCompile.Tab, [3 2]);
g.RowHeight = {'1.2x', '1x', 40};
g.ColumnWidth = {'1.3x', '1x'};
g.Padding = [8 8 8 8];

reportPanel = uipanel(g, Title = 'Validation report', ...
    BackgroundColor = obj.COLOR_PANEL, ForegroundColor = [0.22 0.30 0.40], ...
    FontWeight = 'bold');
reportPanel.Layout.Row = 1;
reportPanel.Layout.Column = [1 2];

reportGrid = uigridlayout(reportPanel, [1 1]);
reportGrid.Padding = [4 4 4 4];

obj.HCompile.Report = uitable(reportGrid, ...
    ColumnName = {'Severity', 'Category', 'Where', 'Problem', 'What to do'}, ...
    ColumnWidth = {70, 92, 170, 340, 'auto'}, ...
    Tooltip = 'Select a row and press Go To Issue to jump to the offending item.', ...
    CellSelectionCallback = @(~, evt) obj.onCompile('reportSelected', evt));

wirePanel = uipanel(g, Title = 'Wire program', BackgroundColor = obj.COLOR_PANEL, ...
    ForegroundColor = [0.22 0.30 0.40], FontWeight = 'bold');
wirePanel.Layout.Row = 2;
wirePanel.Layout.Column = 1;

wireGrid = uigridlayout(wirePanel, [1 1]);
wireGrid.Padding = [4 4 4 4];

obj.HCompile.Wire = uitextarea(wireGrid, Editable = 'off', ...
    FontName = 'Consolas', ...
    Value = {'Compile the program to see the records that would be sent.'});

capPanel = uipanel(g, Title = 'Firmware capacity', BackgroundColor = obj.COLOR_PANEL, ...
    ForegroundColor = [0.22 0.30 0.40], FontWeight = 'bold');
capPanel.Layout.Row = 2;
capPanel.Layout.Column = 2;

capGrid = uigridlayout(capPanel, [1 1]);
capGrid.Padding = [4 4 4 4];

obj.HCompile.Capacity = uitable(capGrid, ...
    ColumnName = {'Resource', 'Used', 'Limit'}, ...
    ColumnWidth = {180, 60, 60}, ...
    Tooltip = 'How much of each fixed firmware array this program consumes.');

actions = uigridlayout(g, [1 7]);
actions.Layout.Row = 3;
actions.Layout.Column = [1 2];
actions.ColumnWidth = {110, 110, 120, 130, 160, 190, '1x'};
actions.Padding = [0 4 0 0];
actions.ColumnSpacing = 6;

localButton_(actions, 'Validate', 'Check the program without compiling.', ...
    @(~, ~) obj.onCompile('validate'));

b = localButton_(actions, 'Compile', 'Emit the wire program.', ...
    @(~, ~) obj.onCompile('compile'));
b.BackgroundColor = obj.COLOR_PRIMARY;
b.FontColor = 'w';
b.FontWeight = 'bold';

obj.HCompile.GoTo = localButton_(actions, 'Go To Issue', ...
    'Jump to the item the selected report row is about.', ...
    @(~, ~) obj.onCompile('goto'));

localButton_(actions, 'Copy Program', 'Copy the wire program to the clipboard.', ...
    @(~, ~) obj.onCompile('copy'));

obj.HCompile.Upload = localButton_(actions, 'Upload to Board', ...
    ['Send the compiled program to the connected Teensy.' newline ...
     'Disabled when no board is bound.'], @(~, ~) obj.onCompile('upload'));

obj.HCompile.Insert = localButton_(actions, 'Insert Into Protocol...', ...
    ['Create this program''s parameters on a Teensy interface in an open' newline ...
     'Protocol Designer, or export them as JSON.'], @(~, ~) obj.onCompile('insert'));
end


% =========================================================================
function h = localButton_(parent, text, tooltip, callback)
% h = localButton_(parent, text, tooltip, callback)
% A push button with a mandatory tooltip.
h = uibutton(parent, Text = text, Tooltip = tooltip, ButtonPushedFcn = callback);
end


function h = localLabel_(parent, text, row)
% h = localLabel_(parent, text, row)
% A right-aligned field label in column 1 of a grid row.
h = uilabel(parent, Text = text, HorizontalAlignment = 'right');
h.Layout.Row = row;
h.Layout.Column = 1;
end
