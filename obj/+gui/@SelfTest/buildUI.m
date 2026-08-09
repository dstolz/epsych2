function buildUI(self)
% buildUI(self)
% Build the self-test window: toolbar, group tree, results table, and detail
% pane.
%
% See also: gui.SelfTest, epsych.SelfTest.catalog
arguments
    self
end

C = epsych.SelfTest.catalog();

f = uifigure('Name', 'EPsych Self-Test', ...
    'Tag', 'RunExptSelfTest', ...
    'Position', [100 100 1040 620]);
f.UserData = self;
f.CloseRequestFcn = @(~,~) self.onClose;
self.H.figure = f;
movegui(f, 'center');

g = uigridlayout(f, [3 1]);
g.RowHeight = {'fit', '1x', 24};
g.RowSpacing = 8;
g.Padding = [10 10 10 10];

% ---------- Toolbar ----------------------------------------------------
gTop = uigridlayout(g, [2 6]);
gTop.Layout.Row = 1; gTop.Layout.Column = 1;
gTop.RowHeight   = {26, 26};
gTop.ColumnWidth = {230, 230, 230, '1x', 110, 110};
gTop.RowSpacing = 6; gTop.ColumnSpacing = 8;
gTop.Padding = [0 0 0 0];

% Opt-ins for the checks that touch live state. Wording states the cost
% up front: an operator should not have to guess what "invasive" means.
self.H.optConnect = uicheckbox(gTop, ...
    'Text', 'Connect hardware interfaces', ...
    'Value', self.Engine.IncludeHardwareConnect, ...
    'Tooltip', ['Connect every interface in the protocol, run each backend''s own' newline ...
                'invasive self-test, then restore the connection state found.' newline ...
                'Disabled while a session is running.'], ...
    'ValueChangedFcn', @(~,~) self.onOptionChanged);
self.H.optConnect.Layout.Row = 1; self.H.optConnect.Layout.Column = 1;

self.H.optBoxFig = uicheckbox(gTop, ...
    'Text', 'Launch the Box GUI', ...
    'Value', self.Engine.IncludeBoxFig, ...
    'Tooltip', ['Launch the configured box GUI against a synthetic runtime and close it.' newline ...
                'ep_GenericGUI allows only one instance, so an open box GUI will be replaced.'], ...
    'ValueChangedFcn', @(~,~) self.onOptionChanged);
self.H.optBoxFig.Layout.Row = 1; self.H.optBoxFig.Layout.Column = 2;

self.H.optStateCycle = uicheckbox(gTop, ...
    'Text', 'Cycle the live GUI state', ...
    'Value', self.Engine.IncludeGuiStateCycle, ...
    'Tooltip', ['Drive the session window through each program state to verify which' newline ...
                'controls are enabled, then restore it. The window will flicker briefly.'], ...
    'ValueChangedFcn', @(~,~) self.onOptionChanged);
self.H.optStateCycle.Layout.Row = 1; self.H.optStateCycle.Layout.Column = 3;

gVerb = uigridlayout(gTop, [1 2]);
gVerb.Layout.Row = 2; gVerb.Layout.Column = 1;
gVerb.ColumnWidth = {70, '1x'};
gVerb.Padding = [0 0 0 0]; gVerb.ColumnSpacing = 4;

lbl = uilabel(gVerb, 'Text', 'Verbosity:', 'HorizontalAlignment', 'right');
lbl.Layout.Row = 1; lbl.Layout.Column = 1;

self.H.verbosity = uidropdown(gVerb, ...
    'Items', {'0 - critical only', '1 - info', '2 - detailed', '3 - debug', '4 - everything'}, ...
    'ItemsData', 0:4, ...
    'Value', self.Engine.Verbosity, ...
    'Tooltip', ['Verbosity forced while checks run, then restored.' newline ...
                'Full detail always reaches the error log regardless of this setting.'], ...
    'ValueChangedFcn', @(~,~) self.onVerbosityChanged);
self.H.verbosity.Layout.Row = 1; self.H.verbosity.Layout.Column = 2;

self.H.btnCopy = uibutton(gTop, 'Text', 'Copy Report', ...
    'Tooltip', 'Copy the full plain-text report to the clipboard.', ...
    'ButtonPushedFcn', @(~,~) self.onCopyReport);
self.H.btnCopy.Layout.Row = 2; self.H.btnCopy.Layout.Column = 2;

self.H.btnSave = uibutton(gTop, 'Text', 'Save Report...', ...
    'Tooltip', 'Write the report to the .error_logs directory.', ...
    'ButtonPushedFcn', @(~,~) self.onSaveReport);
self.H.btnSave.Layout.Row = 2; self.H.btnSave.Layout.Column = 3;

self.H.btnLog = uibutton(gTop, 'Text', 'Open Log', ...
    'Tooltip', 'Open today''s error log, which holds the full detail of every run.', ...
    'ButtonPushedFcn', @(~,~) self.onOpenLog);
self.H.btnLog.Layout.Row = 1; self.H.btnLog.Layout.Column = 5;

self.H.btnRunSelected = uibutton(gTop, 'Text', 'Run Selected', ...
    'ButtonPushedFcn', @(~,~) self.onRunSelected);
self.H.btnRunSelected.Layout.Row = 1; self.H.btnRunSelected.Layout.Column = 6;

self.H.btnRunAll = uibutton(gTop, 'Text', 'Run All', ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.20 0.50 0.90], 'FontColor', 'w', ...
    'ButtonPushedFcn', @(~,~) self.onRunAll);
self.H.btnRunAll.Layout.Row = 2; self.H.btnRunAll.Layout.Column = 6;

% ---------- Main area: group tree | results + detail --------------------
gMain = uigridlayout(g, [1 2]);
gMain.Layout.Row = 2; gMain.Layout.Column = 1;
gMain.ColumnWidth = {240, '1x'};
gMain.RowHeight = {'1x'};
gMain.ColumnSpacing = 8;
gMain.Padding = [0 0 0 0];

pTree = uipanel(gMain, 'Title', 'Check groups');
pTree.Layout.Row = 1; pTree.Layout.Column = 1;
gTree = uigridlayout(pTree, [1 1]);
gTree.Padding = [4 4 4 4];

self.H.tree = uitree(gTree, 'checkbox');
self.H.tree.Layout.Row = 1; self.H.tree.Layout.Column = 1;

nodes = matlab.ui.container.TreeNode.empty(1,0);
for i = 1:numel(C)
    label = char(C(i).label);
    if C(i).mutating
        % Marked so the operator knows which groups can touch live state
        % before pressing Run, not after.
        label = ['[!] ' label];
    end
    nodes(i) = uitreenode(self.H.tree, 'Text', label, 'NodeData', char(C(i).id));
end
self.H.groupNodes = nodes;
self.H.tree.CheckedNodes = nodes;

pResults = uipanel(gMain, 'Title', 'Results');
pResults.Layout.Row = 1; pResults.Layout.Column = 2;
gResults = uigridlayout(pResults, [2 1]);
gResults.RowHeight = {'2x', '1x'};
gResults.RowSpacing = 6;
gResults.Padding = [4 4 4 4];

self.H.table = uitable(gResults, ...
    'ColumnName', {'Group', 'Check', 'Status', 'Result', 'Time (s)'}, ...
    'ColumnWidth', {110, 210, 60, '1x', 70}, ...
    'ColumnEditable', [false false false false false], ...
    'RowName', {}, ...
    'SelectionType', 'row', ...
    'Data', cell(0,5));
self.H.table.Layout.Row = 1; self.H.table.Layout.Column = 1;
self.H.table.SelectionChangedFcn = @(~,evt) self.onSelectionChanged(evt);

self.H.detail = uitextarea(gResults, ...
    'Editable', 'off', ...
    'FontName', 'Consolas', ...
    'Value', {'Select a result to see its details and what to do about it.'});
self.H.detail.Layout.Row = 2; self.H.detail.Layout.Column = 1;

% ---------- Footer ------------------------------------------------------
self.H.status = uilabel(g, 'Text', localInitialStatus(self.Engine));
self.H.status.Layout.Row = 3; self.H.status.Layout.Column = 1;

end

% -----------------------------------------------------------------------
function txt = localInitialStatus(engine)
% Footer text before anything has been run, naming the session under test so
% it is obvious when the window is bound to nothing.
if isempty(engine.RunExpt) || ~isvalid(engine.RunExpt)
    txt = 'No session is open. Environment, path, and timer checks will still run.';
    return
end

txt = sprintf('Ready. Session state %s with %d subject(s).', ...
    string(engine.RunExpt.STATE), numel(engine.RunExpt.CONFIG));
end
