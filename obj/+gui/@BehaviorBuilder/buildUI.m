function buildUI(obj)
% buildUI(obj)
% Construct the builder window: File/Edit/Help menus, protocol panel and
% component palette on the left, the layout canvas in the center, the
% region inspector on the right, and the GUI-settings bar along the bottom.
% Callbacks live as local functions here; canvas mechanics in drawCanvas.m.

pos = gui.BehaviorGUI.getSavedFigurePosition(obj.PREF_TAG, [80 80 1250 760]);
obj.Fig = uifigure('Name','Behavior GUI Builder', 'Tag',obj.PREF_TAG, ...
    'Position',pos, 'AutoResizeChildren','on', ...
    'CloseRequestFcn',@(~,~) localOnClose(obj), 'UserData',obj);
movegui(obj.Fig, 'onscreen');
obj.Fig.KeyPressFcn = @(~,evt) localOnKeyPress(obj, evt);

% --- menus ---------------------------------------------------------------
mFile = uimenu(obj.Fig, 'Text','&File');
uimenu(mFile, 'Text','&New Spec', 'MenuSelectedFcn',@(~,~) localOnNew(obj));
uimenu(mFile, 'Text','&Open Spec...', 'Accelerator','O', ...
    'MenuSelectedFcn',@(~,~) localOnOpen(obj));
obj.RecentMenu = uimenu(mFile, 'Text','Open &Recent');
uimenu(mFile, 'Text','Load &Protocol...', 'Separator','on', ...
    'MenuSelectedFcn',@(~,~) obj.loadProtocol());
uimenu(mFile, 'Text','&Save Spec', 'Accelerator','S', 'Separator','on', ...
    'MenuSelectedFcn',@(~,~) obj.saveSpec(false));
uimenu(mFile, 'Text','Save Spec &As...', ...
    'MenuSelectedFcn',@(~,~) obj.saveSpec(true));
uimenu(mFile, 'Text','&Export GUI Code...', 'Accelerator','E', 'Separator','on', ...
    'MenuSelectedFcn',@(~,~) obj.exportCode());

mEdit = uimenu(obj.Fig, 'Text','&Edit');
uimenu(mEdit, 'Text','&Delete Region', ...
    'MenuSelectedFcn',@(~,~) localDeleteSelected(obj));
uimenu(mEdit, 'Text','&Clear All Regions', ...
    'MenuSelectedFcn',@(~,~) localClearAll(obj));

mHelp = uimenu(obj.Fig, 'Text','&Help');
uimenu(mHelp, 'Text','Builder Documentation', ...
    'MenuSelectedFcn',@(~,~) localOpenDoc());

% --- root layout ---------------------------------------------------------
root = uigridlayout(obj.Fig, [2 3]);
root.RowHeight   = {'1x', 118};
root.ColumnWidth = {255, '1x', 300};
root.Padding = [6 6 6 6];

% --- left column: protocol + palette -------------------------------------
left = uigridlayout(root, [2 1]);
left.Layout.Row = 1; left.Layout.Column = 1;
left.RowHeight = {'fit', '1x'};
left.Padding = [0 0 0 0]; left.RowSpacing = 6;

pnlProt = uipanel(left, 'Title','Protocol');
gp = uigridlayout(pnlProt, [4 1]);
gp.RowHeight = {22, 30, 'fit', 'fit'};
gp.Padding = [6 4 6 4]; gp.RowSpacing = 2;
obj.ProtocolLabel = uilabel(gp, 'Text','(no protocol loaded)', 'FontWeight','bold');
b = uibutton(gp, 'Text','Load Protocol...', ...
    'ButtonPushedFcn',@(~,~) obj.loadProtocol());
b.Layout.Row = 2;
obj.ProtocolSummary = uilabel(gp, 'Text','Load a protocol to list its parameters.', ...
    'WordWrap','on');
obj.ProtocolSummary.Layout.Row = 3;
obj.DegradedBanner = uilabel(gp, 'Text','', ...
    'WordWrap','on', 'FontColor',[0.75 0.3 0], 'Visible','off');
obj.DegradedBanner.Layout.Row = 4;

pnlPal = uipanel(left, 'Title','Components - pick one, then drag on the canvas');
gl = uigridlayout(pnlPal, [2 1]);
gl.RowHeight = {'1x', 66};
gl.Padding = [2 2 2 2]; gl.RowSpacing = 2;
obj.Palette = uitree(gl, ...
    'SelectionChangedFcn',@(s,~) localOnPalette(obj, s));
obj.PaletteDescription = uilabel(gl, 'Text', gui.BehaviorBuilder.PALETTE_HINT, ...
    'WordWrap','on', 'VerticalAlignment','top', ...
    'FontSize',11, 'FontColor',[0.3 0.3 0.35]);

% --- center: canvas ------------------------------------------------------
pnlCanvas = uipanel(root, 'Title','Layout Canvas - drag to place, drag edges to resize');
pnlCanvas.Layout.Row = 1; pnlCanvas.Layout.Column = 2;
gc = uigridlayout(pnlCanvas, [1 1]);
gc.Padding = [2 2 2 2];
obj.Axes = uiaxes(gc);
obj.Axes.Toolbar.Visible = 'off';
disableDefaultInteractivity(obj.Axes);

% --- right: inspector ----------------------------------------------------
pnlIns = uipanel(root, 'Title','Region Inspector');
pnlIns.Layout.Row = 1; pnlIns.Layout.Column = 3;
gi = uigridlayout(pnlIns, [1 1]);
gi.Padding = [2 2 2 2];
obj.InspectorPanel = uipanel(gi, 'BorderType','none', 'Scrollable','on');
obj.InspectorGrid = uigridlayout(obj.InspectorPanel, [8 2]);
obj.InspectorGrid.RowHeight = repmat({26}, 1, 8);
obj.InspectorGrid.ColumnWidth = {80, '1x'};
obj.InspectorGrid.RowSpacing = 4;

% --- bottom: GUI settings ------------------------------------------------
pnlSet = uipanel(root, 'Title','Generated GUI Settings');
pnlSet.Layout.Row = 2; pnlSet.Layout.Column = [1 3];
gs = uigridlayout(pnlSet, [2 8]);
gs.RowHeight = {26, 26};
gs.ColumnWidth = {90, '1x', 90, '1x', 110, 110, 110, 130};
gs.Padding = [6 4 6 4]; gs.RowSpacing = 4;

uilabel(gs, 'Text','Class name:');
obj.ClassNameField = uieditfield(gs, ...
    'ValueChangedFcn',@(s,~) localOnClassName(obj, s));
uilabel(gs, 'Text','Window title:');
obj.WindowNameField = uieditfield(gs, ...
    'ValueChangedFcn',@(s,~) localOnSetting(obj, 'WindowName', s.Value));
uilabel(gs, 'Text','Window size:');
obj.SizeWField = uieditfield(gs, 'numeric', 'Limits',[200 4000], ...
    'RoundFractionalValues','on', ...
    'ValueChangedFcn',@(s,~) localOnSize(obj, 1, s.Value));
obj.SizeHField = uieditfield(gs, 'numeric', 'Limits',[200 4000], ...
    'RoundFractionalValues','on', ...
    'ValueChangedFcn',@(s,~) localOnSize(obj, 2, s.Value));
uilabel(gs, 'Text','w x h (px)');

uilabel(gs, 'Text','Grid rows:');
obj.RowsSpinner = uispinner(gs, 'Limits',[1 obj.MAX_GRID], 'Step',1, ...
    'RoundFractionalValues','on', ...
    'ValueChangedFcn',@(s,~) localOnGridSize(obj, 'Rows', s));
uilabel(gs, 'Text','Grid cols:');
obj.ColsSpinner = uispinner(gs, 'Limits',[1 obj.MAX_GRID], 'Step',1, ...
    'RoundFractionalValues','on', ...
    'ValueChangedFcn',@(s,~) localOnGridSize(obj, 'Cols', s));
obj.PsychTypeDD = uidropdown(gs, 'Items',{'none','Staircase','Detection'}, ...
    'Tooltip','Psych analysis for History / Psych Plot / Staircase Plot', ...
    'ValueChangedFcn',@(s,~) localOnPsychType(obj, s));
obj.PsychParamDD = uidropdown(gs, 'Items',{'(choose parameter)'}, ...
    'Tooltip','Parameter the analysis tracks', ...
    'ValueChangedFcn',@(s,~) localOnPsychParam(obj, s));
obj.PsychTargetDD = uidropdown(gs, 'Items',localBitMaskNames(), ...
    'Tooltip','Detection only: target trial type', ...
    'ValueChangedFcn',@(s,~) localOnPsychTarget(obj, s));
uibutton(gs, 'Text','Export GUI Code...', 'FontWeight','bold', ...
    'ButtonPushedFcn',@(~,~) obj.exportCode());

obj.refreshRecentMenu_;
end


% =========================================================================
% Local callbacks (local functions in a method file share the class's access)
% =========================================================================
function localOnClose(obj)
if obj.Dirty
    sel = uiconfirm(obj.Fig, 'Save the layout spec before closing?', ...
        'Unsaved changes', 'Options',{'Save','Discard','Cancel'}, ...
        'DefaultOption','Save', 'CancelOption','Cancel');
    switch sel
        case 'Save'
            if ~obj.saveSpec(false), return, end
        case 'Cancel'
            return
    end
end
delete(obj);
end

function localOnKeyPress(obj, evt)
if strcmp(evt.Key, 'delete') || strcmp(evt.Key, 'backspace')
    localDeleteSelected(obj);
end
end

function localDeleteSelected(obj)
if ~isempty(obj.SelectedId)
    obj.removeRegion(obj.SelectedId);
end
end

function localClearAll(obj)
if isempty(obj.Spec.Regions), return, end
sel = uiconfirm(obj.Fig, 'Remove every region from the canvas?', 'Clear All', ...
    'Options',{'Clear All','Cancel'}, 'DefaultOption','Cancel');
if ~strcmp(sel, 'Clear All'), return, end
ids = {obj.Spec.Regions.Id};
for k = 1:numel(ids)
    obj.removeRegion(ids{k});
end
end

function localOnNew(obj)
if obj.Dirty
    sel = uiconfirm(obj.Fig, 'Discard unsaved changes?', 'New Spec', ...
        'Options',{'Discard','Cancel'}, 'DefaultOption','Cancel');
    if ~strcmp(sel, 'Discard'), return, end
end
obj.resetSpec_;
end

function localOnOpen(obj)
if obj.Dirty
    sel = uiconfirm(obj.Fig, 'Discard unsaved changes?', 'Open Spec', ...
        'Options',{'Discard','Cancel'}, 'DefaultOption','Cancel');
    if ~strcmp(sel, 'Discard'), return, end
end
[f,p] = uigetfile({['*' gui.BehaviorBuilder.SPEC_EXT], ...
    'Behavior layout spec (*.eblt)'}, 'Open Layout Spec');
if isequal(f, 0), return, end
obj.openSpec(fullfile(p, f));
end

function localOnPalette(obj, tree)
node = tree.SelectedNodes;
if isempty(node) || isempty(node(1).NodeData) % nothing, or a category header
    obj.PaletteDescription.Text = gui.BehaviorBuilder.PALETTE_HINT;
    obj.armType_('');
    return
end
type = node(1).NodeData;
e = gui.BehaviorBuilder.catalogEntry(type);
obj.PaletteDescription.Text = e.Description; % informative even when gated
if e.NeedsPsych && ~obj.psychSatisfies_(e)
    uialert(obj.Fig, sprintf('%s needs a psych analysis. Choose one in the settings bar below first.', ...
        e.Display), 'Psych analysis required', 'Icon','info');
    tree.SelectedNodes = [];
    obj.armType_('');
    return
end
obj.armType_(type);
end

function localOnClassName(obj, src)
v = char(src.Value);
if ~isvarname(v)
    uialert(obj.Fig, sprintf('"%s" is not a valid MATLAB class name.', v), ...
        'Invalid class name');
    src.Value = obj.Spec.ClassName;
    return
end
localOnSetting(obj, 'ClassName', v);
end

function localOnSetting(obj, field, value)
obj.setSpecField_(field, char(value));
end

function localOnSize(obj, ix, value)
sz = obj.Spec.DefaultSize;
sz(ix) = round(value);
obj.setSpecField_('DefaultSize', sz);
end

function localOnGridSize(obj, field, src)
n = round(src.Value);
ok = obj.resizeGrid_(field, n);
if ~ok
    src.Value = obj.Spec.Grid.(field); % refused: regions would fall outside
end
end

function localOnPsychType(obj, src)
ok = obj.setPsychType_(src.Value);
if ~ok
    src.Value = obj.Spec.Psych.Type;
end
end

function localOnPsychParam(obj, src)
v = src.Value;
if strcmp(v, '(choose parameter)'), v = ''; end
p = obj.Spec.Psych;
p.Parameter = v;
obj.setSpecField_('Psych', p);
end

function localOnPsychTarget(obj, src)
v = src.Value;
if strcmp(v, '(any)'), v = ''; end
p = obj.Spec.Psych;
p.TargetTrialType = v;
obj.setSpecField_('Psych', p);
end

function names = localBitMaskNames()
names = [{'(any)'}, cellstr(string(enumeration('epsych.BitMask')))'];
end

function localOpenDoc()
root = fileparts(which('epsych_startup'));
docFile = fullfile(root, 'documentation', 'gui', 'gui_BehaviorBuilder.md');
if isfile(docFile)
    open(docFile);
else
    web('https://github.com/dstolz/epsych2/wiki', '-browser');
end
end
