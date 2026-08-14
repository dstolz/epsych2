function buildUI(self)
% buildUI(self)
% Build the manager window and every control in it.
%
% Three rows: an action strip, the project/subject split, and a status line.
% Projects are a uilistbox rather than a uitree -- they are a flat set, and a
% listbox gives arrow-key and type-ahead navigation for free. Subjects are a
% uitable because each row needs its own box assignment before it is committed,
% which neither a checkbox tree nor a listbox can hold.
%
% See also: gui.SubjectManager.refresh, gui.SubjectManager.addToSession
arguments
    self
end

pos = gui.BoxGUI.getSavedFigurePosition(self.PREF_TAG, self.DEFAULT_POSITION);

f = uifigure('Name','Subjects & Projects', 'Tag', self.FIGURE_TAG, ...
    'Position', pos, ...
    'WindowKeyPressFcn', @(~,evt) self.onKeyPress_(evt));
f.UserData = self;
f.CloseRequestFcn = @(~,~) delete(self);
movegui(f, 'onscreen');
self.H.figure = f;

% ---------- Menus -------------------------------------------------------
mFile = uimenu(f, 'Text','File');
uimenu(mFile, 'Text','&Refresh', 'Accelerator','R', ...
    'MenuSelectedFcn', @(~,~) self.refresh());
uimenu(mFile, 'Text','Roster &File...', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.onChooseRosterFile_());
uimenu(mFile, 'Text','&Import from Config...', ...
    'MenuSelectedFcn', @(~,~) self.onImportFromConfig_());
uimenu(mFile, 'Text','&Export CSV...', ...
    'MenuSelectedFcn', @(~,~) self.onExportCsv_());
uimenu(mFile, 'Text','&Close', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) delete(self));

mSubject = uimenu(f, 'Text','Subject');
self.H.mnu_new_subject = uimenu(mSubject, 'Text','&New Subject...', 'Accelerator','N', ...
    'MenuSelectedFcn', @(~,~) self.onNewSubject_());
self.H.mnu_edit_subject = uimenu(mSubject, 'Text','&Edit Subject...', ...
    'MenuSelectedFcn', @(~,~) self.onEditSubject_());
self.H.mnu_add_to_project = uimenu(mSubject, 'Text','&Add to Project', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.onAddToProject_());
self.H.mnu_remove_from_project = uimenu(mSubject, 'Text','&Remove from Project', ...
    'MenuSelectedFcn', @(~,~) self.onRemoveFromProject_());
self.H.mnu_retire = uimenu(mSubject, 'Text','Re&tire', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.onToggleRetired_());
% Deleting from the roster is menu-only and confirmed. The Delete key is
% bound to Remove from Project, which is the reversible one.
self.H.mnu_delete_subject = uimenu(mSubject, 'Text','&Delete from Roster...', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.onDeleteSubject_());

mProject = uimenu(f, 'Text','Project');
uimenu(mProject, 'Text','&New Project...', ...
    'MenuSelectedFcn', @(~,~) self.onNewProject_());
self.H.mnu_edit_project = uimenu(mProject, 'Text','&Edit Project...', ...
    'MenuSelectedFcn', @(~,~) self.onEditProject_());
self.H.mnu_delete_project = uimenu(mProject, 'Text','&Delete Project...', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.onDeleteProject_());

mSession = uimenu(f, 'Text','Session');
self.H.mnu_add_to_session = uimenu(mSession, 'Text','Add &Checked to Session', ...
    'MenuSelectedFcn', @(~,~) self.addToSession());
self.H.mnu_set_protocol = uimenu(mSession, 'Text','Set &Protocol for Checked...', ...
    'MenuSelectedFcn', @(~,~) self.onSetProtocol_(true));

% ---------- Root layout -------------------------------------------------
g = uigridlayout(f, [3 1]);
g.RowHeight = {'fit', '1x', 22};
g.Padding = [10 8 10 8];
g.RowSpacing = 8;

% ---------- Row 1: action strip -----------------------------------------
% Text buttons rather than a uitoolbar: these read better as words than as
% 16x16 pixel art, and there is room for them.
gTop = uigridlayout(g, [1 5]);
gTop.Layout.Row = 1;
gTop.ColumnWidth = {80, 110, 110, 140, '1x'};
gTop.Padding = [0 0 0 0];
gTop.ColumnSpacing = 6;

uibutton(gTop, 'Text','Refresh', 'ButtonPushedFcn', @(~,~) self.refresh());
uibutton(gTop, 'Text','New Project...', 'ButtonPushedFcn', @(~,~) self.onNewProject_());
uibutton(gTop, 'Text','Roster File...', 'ButtonPushedFcn', @(~,~) self.onChooseRosterFile_());
uibutton(gTop, 'Text','Import from Config...', 'ButtonPushedFcn', @(~,~) self.onImportFromConfig_());

self.H.rosterLabel = uilabel(gTop, 'Text','', 'HorizontalAlignment','right', ...
    'FontColor',[0.35 0.38 0.42]);

% ---------- Row 2: projects | subjects ----------------------------------
gMain = uigridlayout(g, [1 2]);
gMain.Layout.Row = 2;
gMain.ColumnWidth = {260, '1x'};
gMain.Padding = [0 0 0 0];
gMain.ColumnSpacing = 10;

% --- left: project list + per-project summary
gLeft = uigridlayout(gMain, [3 1]);
gLeft.Layout.Column = 1;
gLeft.RowHeight = {'1x', 28, 'fit'};
gLeft.Padding = [0 0 0 0];
gLeft.RowSpacing = 6;

self.H.projectList = uilistbox(gLeft, ...
    'Items', {self.ALL_SUBJECTS}, ...
    'Multiselect','off', ...
    'ValueChangedFcn', @(~,~) self.onProjectChanged_());
self.H.projectList.Layout.Row = 1;

gProjBtns = uigridlayout(gLeft, [1 3]);
gProjBtns.Layout.Row = 2;
gProjBtns.ColumnWidth = {'1x','1x','1x'};
gProjBtns.Padding = [0 0 0 0];
gProjBtns.ColumnSpacing = 4;
uibutton(gProjBtns, 'Text','New...', 'ButtonPushedFcn', @(~,~) self.onNewProject_());
self.H.btnEditProject = uibutton(gProjBtns, 'Text','Edit...', ...
    'ButtonPushedFcn', @(~,~) self.onEditProject_());
self.H.btnDeleteProject = uibutton(gProjBtns, 'Text','Delete', ...
    'ButtonPushedFcn', @(~,~) self.onDeleteProject_());

% Read-only summary so the operator can see what a project will apply
% without opening the edit dialog.
self.H.projectSummary = uilabel(gLeft, 'Text','', 'WordWrap','on', ...
    'VerticalAlignment','top', 'FontColor',[0.35 0.38 0.42]);
self.H.projectSummary.Layout.Row = 3;

% --- right: filter strip, table, action bar
gRight = uigridlayout(gMain, [3 1]);
gRight.Layout.Column = 2;
gRight.RowHeight = {28, '1x', 32};
gRight.Padding = [0 0 0 0];
gRight.RowSpacing = 6;

gFilter = uigridlayout(gRight, [1 4]);
gFilter.Layout.Row = 1;
gFilter.ColumnWidth = {'1x', 110, 70, 180};
gFilter.Padding = [0 0 0 0];
gFilter.ColumnSpacing = 6;

% ValueChangingFcn so filtering happens as the operator types. The match is a
% plain case-insensitive contains, never a regex: typing 'M(1' must narrow the
% list, not raise an error.
self.H.filter = uieditfield(gFilter, 'text', ...
    'Placeholder','Filter subjects...', ...
    'ValueChangingFcn', @(~,evt) self.onFilterChanged_(evt.Value), ...
    'ValueChangedFcn', @(~,~) self.onFilterChanged_());

self.H.showRetired = uicheckbox(gFilter, 'Text','Show retired', ...
    'Value', localSavedShowRetired(), ...
    'ValueChangedFcn', @(~,~) self.refresh());

uibutton(gFilter, 'Text','Clear', 'ButtonPushedFcn', @(~,~) self.clearFilter_());

self.H.countLabel = uilabel(gFilter, 'Text','', 'HorizontalAlignment','right', ...
    'FontColor',[0.35 0.38 0.42]);

self.H.table = uitable(gRight, ...
    'ColumnName', {'', 'Subject', 'Box', 'Protocol', 'Species', 'Sex', ...
                   'Weight', 'Last Run', 'Status'}, ...
    'ColumnFormat', {'logical', 'char', 'numeric', 'char', 'char', 'char', ...
                     'numeric', 'char', 'char'}, ...
    'ColumnEditable', [true false true false false false false false false], ...
    'ColumnWidth', {30, 140, 50, 200, 90, 70, 60, 130, 70}, ...
    'RowName', {}, ...
    'RowStriping','on', ...
    'SelectionType','row', ...
    'CellEditCallback', @(~,evt) self.onCellEdit_(evt));
self.H.table.Layout.Row = 2;

% Protocol is read-only in the grid on purpose: uitable's ColumnFormat is
% per-column, so a dropdown there would share one item list across every row
% and could not offer each subject its own remembered protocol.
cm = uicontextmenu(f);
uimenu(cm, 'Text','Set Protocol for This Row...', ...
    'MenuSelectedFcn', @(~,~) self.onSetProtocol_(false));
uimenu(cm, 'Text','Set Protocol for Checked Rows...', ...
    'MenuSelectedFcn', @(~,~) self.onSetProtocol_(true));
uimenu(cm, 'Text','Edit Subject...', 'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.onEditSubject_());
self.H.table.ContextMenu = cm;

% The empty-state label occupies the table's cell and is shown instead of it.
self.H.emptyState = uilabel(gRight, 'Text','', ...
    'HorizontalAlignment','center', 'VerticalAlignment','center', ...
    'WordWrap','on', 'Visible','off', 'FontColor',[0.35 0.38 0.42]);
self.H.emptyState.Layout.Row = 2;

gActions = uigridlayout(gRight, [1 7]);
gActions.Layout.Row = 3;
gActions.ColumnWidth = {110, 100, 120, 150, 90, '1x', 190};
gActions.Padding = [0 0 0 0];
gActions.ColumnSpacing = 6;

self.H.btnNewSubject = uibutton(gActions, 'Text','New Subject...', ...
    'ButtonPushedFcn', @(~,~) self.onNewSubject_());
self.H.btnEditSubject = uibutton(gActions, 'Text','Edit...', ...
    'ButtonPushedFcn', @(~,~) self.onEditSubject_());
self.H.btnAddToProject = uibutton(gActions, 'Text','Add to Project', ...
    'ButtonPushedFcn', @(~,~) self.onAddToProject_());
self.H.btnRemoveFromProject = uibutton(gActions, 'Text','Remove from Project', ...
    'ButtonPushedFcn', @(~,~) self.onRemoveFromProject_());
self.H.btnRetire = uibutton(gActions, 'Text','Retire', ...
    'ButtonPushedFcn', @(~,~) self.onToggleRetired_());

uilabel(gActions, 'Text','');   % spacer

self.H.btnAddToSession = uibutton(gActions, 'Text','Add Checked to Session', ...
    'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.52 0.85], 'FontColor',[1 1 1], ...
    'ButtonPushedFcn', @(~,~) self.addToSession());

% ---------- Row 3: status line ------------------------------------------
self.H.status = uilabel(g, 'Text','', 'FontColor',[0.35 0.38 0.42]);
self.H.status.Layout.Row = 3;

end

% -----------------------------------------------------------------------
function tf = localSavedShowRetired()
% Remembered across sessions like the selected project.
tf = false;
if ispref('ep_RunExpt_Subjects','ShowRetired')
    tf = logical(getpref('ep_RunExpt_Subjects','ShowRetired'));
end
end
