function BrowseConfigs(self)
% BrowseConfigs — Select a *.config file from a recursive browser.
% Behavior
%   Displays a modal GUI that lists all "*.config" files under the
%   configured root folder and forwards the selected file to LoadConfig().
arguments
    self (1,1) ep_RunExpt2
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

root = getpref('ep_RunExpt_Setup','ConfigBrowserRootDir',"" );
if strlength(string(root)) == 0
    root = getpref('ep_RunExpt_Setup','CDir',cd);
end
if ~exist(root,'dir'), root = cd; end
root = string(root);

[items, fullpaths] = self.FindConfigFiles(root);
if isempty(fullpaths)
    ontop = self.AlwaysOnTop(false);
    warndlg(sprintf('No "*.config" files found under:\n%s',root),'Browse Configs','modal')
    self.AlwaysOnTop(ontop);
    return
end

ontop = self.AlwaysOnTop(false);

f = uifigure('Name','Select Configuration', ...
    'WindowStyle','modal', ...
    'CloseRequestFcn', @(h,~) self.ConfigBrowserCancel(h), ...
    'Position',[200 200 700 500]);
movegui(f,'center');

f.UserData = struct('Items',items,'FullPaths',fullpaths,'RestoreOnTop',ontop);

g = uigridlayout(f,[3 1]);
g.RowHeight = {22,'1x',36};
g.ColumnWidth = {'1x'};
g.RowSpacing = 8;
g.Padding = [8 8 8 8];

lbl = uilabel(g,'Text',sprintf('Root: %s',root), ...
    'Interpreter','none');
lbl.Layout.Row = 1;
lbl.Layout.Column = 1;

lb = uilistbox(g, ...
    'Items',items, ...
    'Multiselect','off');
lb.Layout.Row = 2;
lb.Layout.Column = 1;
lb.Value = items(1);

gBtn = uigridlayout(g,[1 2]);
gBtn.Layout.Row = 3;
gBtn.Layout.Column = 1;
gBtn.ColumnWidth = {'1x','1x'};
gBtn.RowHeight = {'1x'};
gBtn.ColumnSpacing = 8;
gBtn.Padding = [0 0 0 0];

uibutton(gBtn,'push','Text','Load', ...
    'FontWeight','bold', ...
    'ButtonPushedFcn', @(~,~) self.ConfigBrowserLoad(f,lb));

uibutton(gBtn,'push','Text','Cancel', ...
    'ButtonPushedFcn', @(~,~) self.ConfigBrowserCancel(f));
