function buildUI(self, visible)
% buildUI(self, visible)
% Build the debugger window: source bar, parameter table, colour legend, and
% status line.
%
% The table is the whole window. Everything above it narrows what is listed
% (which protocol, whether hidden parameters show, a name filter) and
% everything below it explains what the colours mean, so a person opening this
% for the first time in the middle of a problem does not have to look up the
% legend elsewhere.
%
% See also: gui.ParameterDebugger, epsych.RunExpt.OpenParameterDebugger
arguments
    self
    visible (1,1) logical = true
end

pos = gui.BoxGUI.getSavedFigurePosition(self.PREF_TAG, self.DEFAULT_POSITION);

f = uifigure('Name','EPsych Parameter Debugger', 'Tag', self.FIGURE_TAG, ...
    'Position', pos, ...
    'Visible', matlab.lang.OnOffSwitchState(visible), ...
    'WindowKeyPressFcn', @(~,evt) self.onKeyPress_(evt));
f.UserData = self;
f.CloseRequestFcn = @(~,~) self.onClose_();
movegui(f, 'onscreen');
self.H.figure = f;

% ---------- Menus -------------------------------------------------------
mParams = uimenu(f, 'Text','Parameters');
self.H.mnu_read_all = uimenu(mParams, 'Text','&Read All', 'Accelerator','A', ...
    'MenuSelectedFcn', @(~,~) self.readAll());
self.H.mnu_read_selected = uimenu(mParams, 'Text','Read &Selected', ...
    'MenuSelectedFcn', @(~,~) self.readSelected());
self.H.mnu_fire = uimenu(mParams, 'Text','&Fire Trigger', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.fireTrigger());
uimenu(mParams, 'Text','Re&build List', 'Accelerator','R', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.refresh());
self.H.mnu_copy = uimenu(mParams, 'Text','&Copy to Clipboard', 'Accelerator','C', ...
    'MenuSelectedFcn', @(~,~) self.copyToClipboard());
uimenu(mParams, 'Text','Close', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) delete(self));

mHelp = uimenu(f, 'Text','Help');
uimenu(mHelp, 'Text','Open Current Error Log', ...
    'MenuSelectedFcn', @(~,~) self.openErrorLog_());
uimenu(mHelp, 'Text','Documentation', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) web(EPsychInfo.DocumentationURL, '-browser'));

% ---------- Root layout -------------------------------------------------
g = uigridlayout(f, [4 1]);
g.RowHeight = {'fit', '1x', 'fit', 22};
g.Padding = [10 8 10 8];
g.RowSpacing = 8;

% ---------- Source bar --------------------------------------------------
gTop = uigridlayout(g, [1 8]);
gTop.Layout.Row = 1;
gTop.RowHeight = {24};
gTop.ColumnWidth = {50, 260, 150, 130, 45, 200, '1x', 110};
gTop.ColumnSpacing = 8;
gTop.Padding = [0 0 0 0];

lbl = uilabel(gTop, 'Text','Source:', 'HorizontalAlignment','right');
lbl.Layout.Column = 1;

% Which protocol's parameters are listed. Rebuilt on every refresh, because a
% run replaces RunExpt.RUNTIME and the live entry has to follow it.
self.H.source = uidropdown(gTop, 'Items', {'(none)'}, ...
    'Tooltip', ['Which set of interfaces to list. Before a run these are the ' ...
                'protocol objects a run will use; during one, the live session.'], ...
    'ValueChangedFcn', @(~,~) self.onSourceChanged_());
self.H.source.Layout.Column = 2;

self.H.chkHidden = uicheckbox(gTop, 'Text','Show hidden', 'Value', false, ...
    'Tooltip','List parameters whose Visible flag is false. They are shown greyed.', ...
    'ValueChangedFcn', @(~,~) self.refresh());
self.H.chkHidden.Layout.Column = 3;

% Reading a buffer can pull a megabyte off the device, so Read All leaves them
% alone by default. Reading one on purpose -- double-click, or Read Selected --
% always works regardless of this box.
self.H.chkBuffers = uicheckbox(gTop, 'Text','Include buffers', 'Value', false, ...
    'Tooltip', ['Let Read All read Buffer and Coefficient Buffer parameters. ' ...
                'They can be very large, so they are skipped by default.']);
self.H.chkBuffers.Layout.Column = 4;

lblFilter = uilabel(gTop, 'Text','Find:', 'HorizontalAlignment','right');
lblFilter.Layout.Column = 5;

self.H.filter = uieditfield(gTop, 'text', ...
    'Placeholder','name, module, or interface  (Ctrl+F)', ...
    'ValueChangedFcn', @(~,~) self.onFilterChanged_());
self.H.filter.Layout.Column = 6;

self.H.btnReadSel = uibutton(gTop, 'Text','Read Selected', ...
    'Tooltip','Read the selected rows, buffers included (Ctrl+Enter)', ...
    'ButtonPushedFcn', @(~,~) self.readSelected());
self.H.btnReadSel.Layout.Column = 7;

self.H.btnReadAll = uibutton(gTop, 'Text','Read All (F5)', ...
    'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.52 0.85], 'FontColor',[1 1 1], ...
    'Tooltip','Read every listed parameter from its interface', ...
    'ButtonPushedFcn', @(~,~) self.readAll());
self.H.btnReadAll.Layout.Column = 8;

% ---------- Table -------------------------------------------------------
% Every column is char: the Value column has to hold a numeric scalar, an
% array literal, a file path, and "<stimgen.Tone>" in different rows, and
% uitable's ColumnFormat is per column, not per row.
self.H.table = uitable(g, ...
    'ColumnName', {'Interface / Module', 'Parameter', 'Type', 'Access', ...
                   'Value', 'Unit', 'Flags', 'Last Read'}, ...
    'ColumnFormat', {'char','char','char','char','char','char','char','char'}, ...
    'ColumnEditable', [false false false false true false false false], ...
    'ColumnWidth', {210, 190, 105, 65, 200, 55, 130, '1x'}, ...
    'RowName', {}, ...
    'RowStriping','on', ...
    'SelectionType','row', ...
    'Tooltip', ['Double-click a parameter name to read it. Type into the Value ' ...
                'column to write it.'], ...
    'CellEditCallback', @(~,evt) self.onCellEdit_(evt), ...
    'DoubleClickedFcn', @(~,evt) self.onDoubleClick_(evt), ...
    'SelectionChangedFcn', @(~,~) self.onSelectionChanged_());
self.H.table.Layout.Row = 2;

% ColumnSortable is deliberately left off. Sorting decouples the display order
% from the Data order, and every callback here turns a row index back into an
% hw.Parameter -- a translation that has to be exactly right, because getting
% it wrong means writing to the wrong parameter on live hardware. The Find box
% covers what sorting would be used for, and the natural order (interface,
% then module, then declaration order) is the one the designer and the circuit
% already use.

% Shown in the table's cell when there is nothing to list, so an empty window
% says why rather than just being blank.
self.H.emptyState = uilabel(g, ...
    'Text', 'No protocol is loaded. Load a configuration, or open this window from a protocol.', ...
    'HorizontalAlignment','center', ...
    'FontColor',[0.35 0.38 0.42], ...
    'Visible','off');
self.H.emptyState.Layout.Row = 2;

% ---------- Context menu ------------------------------------------------
cm = uicontextmenu(f);
self.H.cmnu_read = uimenu(cm, 'Text','Read Selected', ...
    'MenuSelectedFcn', @(~,~) self.readSelected());
self.H.cmnu_fire = uimenu(cm, 'Text','Fire Trigger', ...
    'MenuSelectedFcn', @(~,~) self.fireTrigger());
self.H.cmnu_assign = uimenu(cm, 'Text','Assign to Command Window (P)', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.assignToBase());
self.H.cmnu_copy = uimenu(cm, 'Text','Copy to Clipboard', ...
    'MenuSelectedFcn', @(~,~) self.copyToClipboard());
self.H.table.ContextMenu = cm;

% ---------- Legend ------------------------------------------------------
% The colours are the read report, so what they mean belongs in the window,
% not only in the documentation.
gLegend = uigridlayout(g, [1 7]);
gLegend.Layout.Row = 3;
gLegend.RowHeight = {20};
gLegend.ColumnWidth = {50, 60, 70, 65, 60, 75, '1x'};
gLegend.ColumnSpacing = 4;
gLegend.Padding = [0 0 0 0];

uilabel(gLegend, 'Text','Value:', 'FontColor',[0.35 0.38 0.42]);
localSwatch(gLegend, self.COLOR_OK,    'read');
localSwatch(gLegend, self.COLOR_WROTE, 'written');
localSwatch(gLegend, self.COLOR_STALE, 'differs');
localSwatch(gLegend, self.COLOR_FAIL,  'failed');
localSwatch(gLegend, self.COLOR_SKIP,  'not read');

self.H.countLabel = uilabel(gLegend, 'Text','', ...
    'HorizontalAlignment','right', 'FontColor',[0.35 0.38 0.42]);
self.H.countLabel.Layout.Column = 7;

% ---------- Status ------------------------------------------------------
self.H.status = uilabel(g, 'Text','Double-click a parameter name to read it.');
self.H.status.Layout.Row = 4;

end


% -----------------------------------------------------------------------
function localSwatch(parent, color, text)
% One legend entry: a tinted label carrying its own meaning as its text.
uilabel(parent, 'Text', text, ...
    'BackgroundColor', color, ...
    'HorizontalAlignment','center', ...
    'FontColor',[0.25 0.28 0.32]);
end
