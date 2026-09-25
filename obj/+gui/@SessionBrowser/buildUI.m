function buildUI(self, visible)
% buildUI(self, visible)
% Build the browser window: a header naming the subject, the session table,
% a details pane for the selected file, and the Review button.
%
% The table carries only what an operator scans a column for -- when, how
% long, how many trials, which box and paradigm, whether there is video, and
% what a review of it will show. Everything else about the selected file (the
% full path, the version it ran under, the operator's notes) is in the pane
% below, where it has room to be read.
%
% See also: gui.SessionBrowser, gui.SubjectManager
arguments
    self
    visible (1,1) logical = true
end

pos = gui.BehaviorGUI.getSavedFigurePosition(self.PREF_TAG, self.DEFAULT_POSITION);
pos = gui.fitPositionToMonitor(pos);

f = uifigure('Name', sprintf('Data Files — %s', self.SubjectName), ...
    'Tag', self.FIGURE_TAG, ...
    'Position', pos, ...
    'Visible', matlab.lang.OnOffSwitchState(visible), ...
    'WindowKeyPressFcn', @(~,evt) self.onKeyPress_(evt));
f.UserData = self;
f.CloseRequestFcn = @(~,~) delete(self);
self.H.figure = f;

% ---------- Root layout -------------------------------------------------
% Row 2 is the "session running" banner, collapsed to zero height until a
% session starts. A hidden child still reserves a 'fit' row, so the row height
% itself is what updateEnableStates_ toggles.
g = uigridlayout(f, [5 1]);
g.RowHeight = {26, 0, '1x', 150, 30};
g.Padding = [10 8 10 8];
g.RowSpacing = 8;
self.H.root = g;

% ---------- Row 1: who, how many, and the scan controls -----------------
gTop = uigridlayout(g, [1 4]);
gTop.Layout.Row = 1;
gTop.ColumnWidth = {'fit', '1x', 210, 90};
gTop.Padding = [0 0 0 0];
gTop.ColumnSpacing = 10;

self.H.title = uilabel(gTop, 'Text', char(self.SubjectName), ...
    'FontWeight', 'bold', 'FontSize', 14);
self.H.count = uilabel(gTop, 'Text', '', 'FontColor', self.MUTED);

% Off by default: a session that saved normally has a recovery copy too, so
% they would double the list. They are the only record of a Preview run, a
% crash, or a save that was declined -- which is when someone comes looking.
self.H.chkRecovery = uicheckbox(gTop, 'Text', 'Include crash-recovery files', ...
    'Value', logical(getpref(self.PREF_GROUP, 'SessionBrowserRecovery', false)), ...
    'Tooltip', ['Also list the copies every session writes as it runs. They are ' ...
        'the only record of a Preview run, a crash, or a save that was declined.'], ...
    'ValueChangedFcn', @(~,~) self.onRecoveryToggled_());

self.H.btnRescan = uibutton(gTop, 'Text', 'Rescan', ...
    'Tooltip', 'Look for new or changed files (F5)', ...
    'ButtonPushedFcn', @(~,~) self.rescan());

% ---------- Row 2: session-running banner -------------------------------
self.H.banner = uilabel(g, ...
    'Text', ['  A session is running. Reviewing and rescanning come back ' ...
        'once it has stopped.'], ...
    'BackgroundColor', [1.00 0.95 0.85], 'FontColor', [0.60 0.32 0.02], ...
    'Visible', 'off');
self.H.banner.Layout.Row = 2;

% ---------- Row 3: the sessions -----------------------------------------
% Every column sorts by value from its header (see displayTable_ for how). The
% sort is the display's business only: every callback works in the DATA row
% uitable reports (Selection, InteractionInformation.Row), never the display
% order. Widths leave room for the sort arrow, which a header shares with its
% label.
self.H.table = uitable(g, ...
    'ColumnName', {'Date','Start','Duration','Trials','Box','Paradigm', ...
                   'Video','Source','Review','File'}, ...
    'ColumnWidth', {125, 60, 82, 62, 52, 170, 58, 115, 82, '1x'}, ...
    'RowName', {}, ...
    'RowStriping', 'on', ...
    'SelectionType', 'row', ...
    'Multiselect', 'off', ...
    'ColumnSortable', true, ...
    'Tooltip', ['Click a header to sort. Double-click a row, or press Enter, ' ...
        'to review that session.'], ...
    'SelectionChangedFcn', @(~,~) self.onSelectionChanged_(), ...
    'DoubleClickedFcn', @(~,evt) self.onDoubleClick_(evt));
self.H.table.Layout.Row = 3;

cm = uicontextmenu(f);
self.H.cmnu_review = uimenu(cm, 'Text', 'Review Session', ...
    'MenuSelectedFcn', @(~,~) self.review());
self.H.cmnu_copy = uimenu(cm, 'Text', 'Copy File Path', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) self.copyPath_());
self.H.cmnu_folder = uimenu(cm, 'Text', 'Show in Folder', ...
    'MenuSelectedFcn', @(~,~) self.showInFolder_());
cm.ContextMenuOpeningFcn = @(~,evt) self.onContextMenuOpening_(evt);
self.H.table.ContextMenu = cm;

% Shown in the table's cell instead of it when nothing was found, so an empty
% window says where it looked rather than just being blank.
self.H.emptyState = uilabel(g, 'Text', '', ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
    'WordWrap', 'on', 'Visible', 'off', 'FontColor', self.MUTED);
self.H.emptyState.Layout.Row = 3;

% ---------- Row 4: details of the selected file -------------------------
self.H.details = uitextarea(g, 'Editable', 'off', 'Value', {''}, ...
    'FontColor', [0.20 0.22 0.26]);
self.H.details.Layout.Row = 4;

% ---------- Row 5: where it looked, and the action ----------------------
gBottom = uigridlayout(g, [1 2]);
gBottom.Layout.Row = 5;
gBottom.ColumnWidth = {'1x', 170};
gBottom.Padding = [0 0 0 0];
gBottom.ColumnSpacing = 10;

self.H.status = uilabel(gBottom, 'Text', '', 'FontColor', self.MUTED);

self.H.btnReview = uibutton(gBottom, 'Text', 'Review Session', ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.20 0.52 0.85], 'FontColor', [1 1 1], ...
    'Enable', 'off', ...
    'ButtonPushedFcn', @(~,~) self.review());

end
