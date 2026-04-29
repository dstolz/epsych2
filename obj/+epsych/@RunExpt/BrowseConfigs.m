function BrowseConfigs(self)
% BrowseConfigs — Select a *.ecfg file from a recursive browser.
% Behavior
%   Displays a modal GUI that lists all "*.ecfg" files under the
%   configured root folder and forwards the selected file to LoadConfig().
arguments
    self
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
    warndlg(sprintf('No "*.ecfg" files found under:\n%s',root),'Browse Configs','modal')
    self.AlwaysOnTop(ontop);
    return
end

ontop = self.AlwaysOnTop(false);

f = uifigure('Name','Select Configuration', ...
    'WindowStyle','modal', ...
    'CloseRequestFcn', @(h,~) self.ConfigBrowserCancel(h), ...
    'Position',[200 200 400 500]);
movegui(f,'center');

% NOTE: Keep legacy fields (Items/FullPaths) so ConfigBrowserLoad() and
% other callbacks continue to work unchanged.
f.UserData = struct( ...
    'AllItems',items, ...
    'AllFullPaths',fullpaths, ...
    'FilteredItems',items, ...
    'FilteredFullPaths',fullpaths, ...
    'Items',items, ...
    'FullPaths',fullpaths, ...
    'RestoreOnTop',ontop, ...
    'LoadButton',[]);

g = uigridlayout(f,[4 1]);
g.RowHeight = {22,22,'1x',36};
g.ColumnWidth = {'1x'};
g.RowSpacing = 8;
g.Padding = [8 8 8 8];

lbl = uilabel(g,'Text',sprintf('Root: %s',root), ...
    'Interpreter','none');
lbl.Layout.Row = 1;
lbl.Layout.Column = 1;

% Search field (live filtering)
edtSearch = uieditfield(g,'text', ...
    'Placeholder','Search (live filter)...', ...
    'ValueChangedFcn', @(src,~) localFilter(src,f));
edtSearch.Layout.Row = 2;
edtSearch.Layout.Column = 1;

lb = uilistbox(g, ...
    'Items',items, ...
    'Multiselect','off');
lb.Layout.Row = 3;
lb.Layout.Column = 1;
lb.Value = items(1);

% Use ValueChangingFcn for live keypress filtering
edtSearch.ValueChangingFcn = @(src,evt) localFilterValueChanging(evt.Value,f,lb);

% Route figure keypresses into the search field (reliable focus substitute)

f.WindowKeyPressFcn = @(~,evt) localFigureKeyPress(evt,edtSearch,f,lb);

gBtn = uigridlayout(g,[1 2]);
gBtn.Layout.Row = 4;
gBtn.Layout.Column = 1;
gBtn.ColumnWidth = {'1x','1x'};
gBtn.RowHeight = {'1x'};
gBtn.ColumnSpacing = 8;
gBtn.Padding = [0 0 0 0];

btnLoad = uibutton(gBtn,'push','Text','Load', ...
    'FontWeight','bold', ...
    'ButtonPushedFcn', @(~,~) localLoad(self,f,lb));

uibutton(gBtn,'push','Text','Cancel', ...
    'ButtonPushedFcn', @(~,~) self.ConfigBrowserCancel(f));

ud = f.UserData;
ud.LoadButton = btnLoad;
f.UserData = ud;

end

function localFigureKeyPress(evt,edtSearch,f,lb)
% Emulate focus by piping keystrokes to the search field.
% Note: uieditfield (uifigure) does not support focus() or a Focus property.

if isempty(evt) || ~isvalid(edtSearch)
    return
end

key = string(evt.Key);
ch = string(evt.Character);

% Ignore pure modifier keys
if any(key == ["shift","control","alt","command","capslock","tab"])
    return
end

val = string(edtSearch.Value);

switch key
    case "backspace"
        if strlength(val) > 0
            val = extractBefore(val, strlength(val));
        end
    case "escape"
        val = "";
    case "return"
        % do nothing
    otherwise
        if strlength(ch) == 1
            val = val + ch;
        end
end

edtSearch.Value = char(val);
applyFilter(string(edtSearch.Value), f, lb);
end

function localFilter(src,f)
% Fallback (e.g., programmatic changes)
val = string(src.Value);
applyFilter(val,f);
end

function localFilterValueChanging(val,f,lb)
% Live filtering on each key press
val = string(val);
applyFilter(val,f,lb);
end

function localLoad(self,f,lb)
% Ensure legacy fields exist at click time (ConfigBrowserLoad compatibility)
ud = f.UserData;
if ~isstruct(ud)
    ud = struct;
end

% Prefer the current filtered lists if present, else fall back to All*
if isfield(ud,'FilteredItems') && isfield(ud,'FilteredFullPaths')
    ud.Items = ud.FilteredItems;
    ud.FullPaths = ud.FilteredFullPaths;
elseif isfield(ud,'AllItems') && isfield(ud,'AllFullPaths')
    ud.Items = ud.AllItems;
    ud.FullPaths = ud.AllFullPaths;
end

f.UserData = ud;
self.ConfigBrowserLoad(f,lb);
end

function applyFilter(searchText,f,lb)
if nargin < 3
    lb = findobj(f,'Type','uilistbox');
end

ud = f.UserData;

if strlength(searchText) == 0
    items = ud.AllItems;
    paths = ud.AllFullPaths;
else
    mask = contains(lower(ud.AllItems), lower(searchText));
    items = ud.AllItems(mask);
    paths = ud.AllFullPaths(mask);
end

if isempty(items)
    lb.Items = {'(no matches)'};
    lb.Value = '(no matches)';
    if ~isempty(ud.LoadButton) && isvalid(ud.LoadButton)
        ud.LoadButton.Enable = 'off';
    end
else
    lb.Items = items;
    lb.Value = items(1);
    if ~isempty(ud.LoadButton) && isvalid(ud.LoadButton)
        ud.LoadButton.Enable = 'on';
    end
end

% Keep both new and legacy fields in sync
ud.FilteredItems = items;
ud.FilteredFullPaths = paths;
ud.Items = items;
ud.FullPaths = paths;

f.UserData = ud;
end
