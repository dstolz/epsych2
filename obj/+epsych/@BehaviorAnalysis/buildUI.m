function buildUI(self, visible)
% buildUI(self, visible)
% Build the window: header, notification bar, browser beside the tabs, and
% the status bar, with the menus and the toolbar. The views themselves are
% built per root (attachStudy_), into the containers made here.
%
% Layout (root grid, 4 rows):
%   1  HEADER, 64 px: the root and its counts on the first line; the
%      analysis settings everyone edits most on the second (preset,
%      analysis, parameter, trial window, test trials, trial types)
%   2  NOTIFICATION BAR: zero height unless there is something to act on
%      (a store that cannot be written, catalog warnings). A hidden child
%      still reserves a 'fit' row, so the row height is what is toggled.
%   3  BODY: the browser and the tabs
%   4  STATUS BAR
%
% See also: epsych.BehaviorAnalysis, gui.SessionBrowser.buildUI
arguments
    self
    visible (1,1) logical = true
end

% Behind ispref: the shared getter reads getpref(group, name, default), which
% would create the preference for a window nobody has placed yet.
pos = self.DEFAULT_POSITION;
if ispref(self.PREF_TAG, 'FigurePosition')
    pos = gui.BehaviorGUI.getSavedFigurePosition(self.PREF_TAG, self.DEFAULT_POSITION);
end
pos = gui.fitPositionToMonitor(pos);

f = uifigure('Name', 'Behavior Analysis', ...
    'Tag', self.FIGURE_TAG, ...
    'Position', pos, ...
    'Visible', matlab.lang.OnOffSwitchState(visible), ...
    'WindowKeyPressFcn', @(~, evt) self.onKeyPress_(evt));
f.UserData = self;
f.CloseRequestFcn = @(~,~) self.onCloseRequest_();
self.H.figure = f;

self.buildMenus_();
self.buildToolbar_();

g = uigridlayout(f, [4 1]);
g.RowHeight = {64, 0, '1x', 26};
g.Padding = [8 6 8 4];
g.RowSpacing = 6;
self.H.root = g;

% ---------- Row 1: header ------------------------------------------------
hd = uigridlayout(g, [2 1]);
hd.Layout.Row = 1;
hd.RowHeight = {24, 26};
hd.Padding = [0 0 0 0];
hd.RowSpacing = 6;
self.H.header = hd;

h1 = uigridlayout(hd, [1 4]);
h1.ColumnWidth = {'1x', 'fit', 'fit', 110};
h1.Padding = [0 0 0 0];
h1.ColumnSpacing = 12;
self.H.lblRoot = uilabel(h1, 'Text', '(no data root open)', 'FontWeight', 'bold', 'FontSize', 13);
self.H.btnOpenRoot = uibutton(h1, 'Text', 'Open Root...', ...
    'Tooltip', 'Choose the folder that holds <Project>/<Subject>/<sessions>.mat (Ctrl+O)', ...
    'ButtonPushedFcn', @(~,~) self.openRoot(""));
self.H.lblCounts = uilabel(h1, 'Text', '', 'FontColor', self.MUTED);
self.H.lblSave = uilabel(h1, 'Text', '', 'HorizontalAlignment', 'right', 'FontWeight', 'bold', ...
    'Tooltip', 'Whether the project file holds every decision made in this window (File > Save Project, Ctrl+S)');

h2 = uigridlayout(hd, [1 12]);
h2.ColumnWidth = {'fit', 170, 'fit', 130, 'fit', 160, 'fit', 110, 'fit', 'fit', 70, '1x'};
h2.Padding = [0 0 0 0];
h2.ColumnSpacing = 6;
uilabel(h2, 'Text', 'Preset');
self.H.ddPreset = uidropdown(h2, 'Items', {'(custom)'}, 'ItemsData', {'::custom'}, ...
    'Tooltip', 'Named analysis settings (and Compare view) kept in the project file', ...
    'ValueChangedFcn', @(~,~) self.onPresetChosen_());
uilabel(h2, 'Text', 'Analysis');
self.H.ddAnalysis = uidropdown(h2, 'Items', {'Staircase', 'Detection (v2)', 'NAFC (v2)'}, ...
    'ItemsData', {'Staircase', 'Detection', 'NAFC'}, 'Value', 'Staircase', ...
    'Tooltip', 'What is analysed. This version analyses staircases; Detection and NAFC are planned.', ...
    'ValueChangedFcn', @(~,~) self.onHeaderEdit_("Analysis"));
uilabel(h2, 'Text', 'Parameter');
self.H.ddParameter = uidropdown(h2, 'Items', {'(auto)'}, 'ItemsData', {''}, ...
    'Tooltip', ['The tracked parameter (a DATA field). (auto) takes each session''s best ' ...
        'candidate, and flags a session whose choice differs from the rest.'], ...
    'ValueChangedFcn', @(~,~) self.onHeaderEdit_("Parameter"));
uilabel(h2, 'Text', 'Window');
self.H.edWindow = uieditfield(h2, 'text', 'Value', 'all', ...
    'Tooltip', ['Trials analysed in every session: "all", "last 100", "first 50", "3-83", ' ...
        '"20+". A session''s own override (Session > Trial Window Override) wins.'], ...
    'ValueChangedFcn', @(~,~) self.onHeaderEdit_("Window"));
self.H.chkTest = uicheckbox(h2, 'Text', 'Exclude test trials', 'Value', true, ...
    'Tooltip', 'Leave out trials run in Preview (isTest)', ...
    'ValueChangedFcn', @(~,~) self.onHeaderEdit_("ExcludeTest"));
uilabel(h2, 'Text', 'Exclude trial types');
self.H.edTypes = uieditfield(h2, 'text', 'Value', '', 'Placeholder', 'none', ...
    'Tooltip', 'TrialType values left out of every analysis, e.g. "2" for reminder trials', ...
    'ValueChangedFcn', @(~,~) self.onHeaderEdit_("ExcludeTrialTypes"));
uilabel(h2, 'Text', '');

% ---------- Row 2: notification bar --------------------------------------
nb = uigridlayout(g, [1 4]);
nb.Layout.Row = 2;
nb.ColumnWidth = {'1x', 'fit', 'fit', 'fit'};
nb.Padding = [8 3 8 3];
nb.BackgroundColor = self.BAR_COLOR;
self.H.bar = nb;
self.H.barText = uilabel(nb, 'Text', '', 'FontColor', self.WARN);
self.H.barStore = uibutton(nb, 'Text', 'Choose store folder...', ...
    'Tooltip', 'Keep this root''s project file in another folder (remembered for this root)', ...
    'ButtonPushedFcn', @(~,~) self.chooseStore_());
self.H.barWarnings = uibutton(nb, 'Text', 'Warnings', ...
    'ButtonPushedFcn', @(~,~) self.showWarnings_());
self.H.barClose = uibutton(nb, 'Text', 'Dismiss', ...
    'ButtonPushedFcn', @(~,~) self.dismissBar_());

% ---------- Row 3: browser + tabs ----------------------------------------
body = uigridlayout(g, [1 2]);
body.Layout.Row = 3;
body.Padding = [0 0 0 0];
body.ColumnSpacing = 8;
self.H.body = body;
self.H.browserHost = uipanel(body, 'BorderType', 'none');
self.H.browserHost.Layout.Column = 1;
self.H.tabs = uitabgroup(body, 'SelectionChangedFcn', @(~,~) self.onTabChanged_());
self.H.tabs.Layout.Column = 2;
self.H.tab = struct();
for name = self.TAB_NAMES
    self.H.tab.(name) = uitab(self.H.tabs, 'Title', char(name));
end
last = string(self.getPref_('LastTab', "Session"));
if ismember(last, self.TAB_NAMES)
    self.H.tabs.SelectedTab = self.H.tab.(last);
end
self.layoutBody_();

% ---------- Row 4: status ------------------------------------------------
self.H.status = uilabel(g, 'Text', '', 'FontColor', self.MUTED);
self.H.status.Layout.Row = 4;

end

