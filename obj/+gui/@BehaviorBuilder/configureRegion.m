function ok = configureRegion(obj, id, isNew)
% ok = configureRegion(obj, id, isNew)
% Open the options dialog for one region. Types without options return true
% immediately. Cancel returns false; on a just-created region (isNew) the
% caller then removes it, so a region is never left half-configured.
%
% Parameter pickers work off the spec's ParameterSnapshot, so they behave
% the same whether the protocol file is present or the spec opened in
% degraded mode.

arguments
    obj
    id (1,:) char
    isNew (1,1) logical = false %#ok<INUSA> (documented flow; caller uses the return)
end

ix = strcmp({obj.Spec.Regions.Id}, id);
assert(any(ix), 'epsych:BehaviorBuilder:BadRegion', 'No region "%s"', id)
r = obj.Spec.Regions(ix);
e = gui.BehaviorBuilder.catalogEntry(r.Type);
if ~e.HasOptions
    ok = true;
    return
end

snap = obj.Spec.ParameterSnapshot;
switch r.Type
    case 'ControlColumn'
        [o, ok] = controlColumnDialog(obj, r, snap);
    case 'ButtonRow'
        [o, ok] = buttonRowDialog(obj, r, snap);
    case 'Monitor'
        [o, ok] = monitorDialog(obj, r, snap);
    case 'Scatter'
        [o, ok] = scatterDialog(obj, r, snap);
    case 'SyringePump'
        [o, ok] = pumpDialog(obj, r);
    otherwise
        ok = true;
        return
end
if ~ok, return, end
obj.Spec.Regions(ix).Options = o;
obj.markDirty_;
end


% =========================================================================
% Per-type dialogs
% =========================================================================
function [o, ok] = controlColumnDialog(obj, r, snap)
% Two-list picker: available writable (and readable) parameters on the left,
% chosen controls on the right as an editable table (Type / autoCommit / Text).
o = r.Options;
trig = snapTriggerStyle(snap);
avail = {snap(~trig).Name}; % writable controls plus Read params (readonly display)

[dlg, g] = modalShell(obj, sprintf('Control Column - %s', orLabel(r)), 700, 430, [2 3]);
g.RowHeight = {'1x', 34};
g.ColumnWidth = {220, 90, '1x'};

lb = uilistbox(g, 'Items',avail, 'Multiselect','on');
lb.Layout.Row = 1; lb.Layout.Column = 1;

bg = uigridlayout(g, [4 1]);
bg.Layout.Row = 1; bg.Layout.Column = 2;
bg.RowHeight = {'1x', 30, 30, '1x'};
bg.Padding = [0 0 0 0];
uilabel(bg, 'Text','');
bAdd = uibutton(bg, 'Text','Add >');
bRem = uibutton(bg, 'Text','< Remove');
uilabel(bg, 'Text','');

types = {'auto','editfield','dropdown','checkbox','readonly'};
tbl = uitable(g, 'ColumnName',{'Parameter','Type','Auto-commit','Label'}, ...
    'ColumnFormat',{'char', types, 'logical', 'char'}, ...
    'ColumnEditable',[false true true true], ...
    'ColumnWidth',{110, 90, 80, 'auto'}, ...
    'Data', controlsToCell(o.Controls));
tbl.Layout.Row = 1; tbl.Layout.Column = 3;

note = uilabel(g, 'Text','An Update button is added automatically when any control is not auto-commit.', ...
    'FontAngle','italic', 'FontSize',11);
note.Layout.Row = 2; note.Layout.Column = [1 3];

bAdd.ButtonPushedFcn = @(~,~) addRows();
bRem.ButtonPushedFcn = @(~,~) removeRows();

ok = runModal(dlg);
if ok
    o.Controls = cellToControls(tbl.Data, snap);
end
delete(dlg);

    function addRows()
        sel = lb.Value;
        if ischar(sel), sel = {sel}; end
        d = tbl.Data;
        have = {};
        if ~isempty(d), have = d(:,1)'; end
        for i = 1:numel(sel)
            if any(strcmp(have, sel{i})), continue, end
            row = snapRow(snap, sel{i});
            t = 'auto';
            if ~isempty(row) && (strcmp(row.Access,'Read') || row.hasExpression)
                t = 'readonly';
            end
            d(end+1,:) = {sel{i}, t, false, ''}; %#ok<AGROW>
        end
        tbl.Data = d;
    end

    function removeRows()
        sel = tbl.Selection; % rows selected in the table
        if isempty(sel), return, end
        d = tbl.Data;
        d(unique(sel(:,1)), :) = [];
        tbl.Data = d;
    end
end

function [o, ok] = buttonRowDialog(obj, r, snap)
o = r.Options;
trig = snapTriggerStyle(snap);
avail = {snap(trig).Name};

[dlg, g] = modalShell(obj, sprintf('Button Row - %s', orLabel(r)), 640, 400, [3 3]);
g.RowHeight = {'1x', 30, 34};
g.ColumnWidth = {220, 90, '1x'};

lb = uilistbox(g, 'Items',avail, 'Multiselect','on');
lb.Layout.Row = 1; lb.Layout.Column = 1;

bg = uigridlayout(g, [4 1]);
bg.Layout.Row = 1; bg.Layout.Column = 2;
bg.RowHeight = {'1x', 30, 30, '1x'};
bg.Padding = [0 0 0 0];
uilabel(bg, 'Text','');
bAdd = uibutton(bg, 'Text','Add >');
bRem = uibutton(bg, 'Text','< Remove');
uilabel(bg, 'Text','');

tbl = uitable(g, 'ColumnName',{'Trigger parameter','Button label'}, ...
    'ColumnFormat',{'char','char'}, ...
    'ColumnEditable',[false true], ...
    'ColumnWidth',{150, 'auto'}, ...
    'Data', buttonsToCell(o.Buttons));
tbl.Layout.Row = 1; tbl.Layout.Column = 3;

cb = uicheckbox(g, 'Text','Include a Screen Capture button at the end of the row', ...
    'Value', o.IncludeScreenCapture);
cb.Layout.Row = 2; cb.Layout.Column = [1 3];

bAdd.ButtonPushedFcn = @(~,~) addRows();
bRem.ButtonPushedFcn = @(~,~) removeRows();

ok = runModal(dlg);
if ok
    o.Buttons = cellToButtons(tbl.Data);
    o.IncludeScreenCapture = logical(cb.Value);
end
delete(dlg);

    function addRows()
        sel = lb.Value;
        if ischar(sel), sel = {sel}; end
        d = tbl.Data;
        have = {};
        if ~isempty(d), have = d(:,1)'; end
        for i = 1:numel(sel)
            if any(strcmp(have, sel{i})), continue, end
            d(end+1,:) = {sel{i}, ''}; %#ok<AGROW>
        end
        tbl.Data = d;
    end

    function removeRows()
        sel = tbl.Selection;
        if isempty(sel), return, end
        d = tbl.Data;
        d(unique(sel(:,1)), :) = [];
        tbl.Data = d;
    end
end

function [o, ok] = monitorDialog(obj, r, snap)
o = r.Options;
avail = {snap.Name};

[dlg, g] = modalShell(obj, sprintf('Parameter Monitor - %s', orLabel(r)), 460, 420, [4 2]);
g.RowHeight = {22, '1x', 28, 28};
g.ColumnWidth = {130, '1x'};

lbl = uilabel(g, 'Text','Parameters to monitor:');
lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];
lb = uilistbox(g, 'Items',avail, 'Multiselect','on');
lb.Layout.Row = 2; lb.Layout.Column = [1 2];
lb.Value = intersect(o.Params, avail);

uilabel(g, 'Text','Poll period (s):');
pf = uieditfield(g, 'numeric', 'Limits',[0.1 60], 'Value', o.PollPeriod);
uilabel(g, 'Text','Style:');
sd = uidropdown(g, 'Items',{'table','text'}, 'Value', o.Style);

ok = runModal(dlg);
if ok
    v = lb.Value;
    if ischar(v), v = {v}; end
    o.Params = reshape(cellstr(v), 1, []);
    o.PollPeriod = pf.Value;
    o.Style = sd.Value;
end
delete(dlg);
end

function [o, ok] = scatterDialog(obj, r, snap)
% Three single-select listboxes rather than dropdowns: a uifigure dropdown's
% popup is clipped to its parent figure, so with a couple dozen parameters
% (routine for a real protocol) the list ran off the bottom of the small
% modal dialog. Listboxes show their full item list inline instead.
o = r.Options;
names = {snap.Name};
AUTO = '(auto)'; NONE = '(none)';
xItems = [{AUTO, 'Trial Number', 'Response'}, names];
cItems = [{NONE, 'Response'}, names];

[dlg, g] = modalShell(obj, sprintf('Parameter Scatter - %s', orLabel(r)), 640, 420, [2 3]);
g.RowHeight = {22, '1x'};
g.ColumnWidth = {'1x', '1x', '1x'};
g.ColumnSpacing = 10;

lblX = uilabel(g, 'Text','X axis:'); lblX.Layout.Row = 1; lblX.Layout.Column = 1;
lblY = uilabel(g, 'Text','Y axis:'); lblY.Layout.Row = 1; lblY.Layout.Column = 2;
lblC = uilabel(g, 'Text','Color by:'); lblC.Layout.Row = 1; lblC.Layout.Column = 3;

lbX = uilistbox(g, 'Items',xItems, 'Value',clampChoice(orAuto(o.XParameter, AUTO), xItems));
lbX.Layout.Row = 2; lbX.Layout.Column = 1;
lbY = uilistbox(g, 'Items',xItems, 'Value',clampChoice(orAuto(o.YParameter, AUTO), xItems));
lbY.Layout.Row = 2; lbY.Layout.Column = 2;
lbC = uilistbox(g, 'Items',cItems, 'Value',clampChoice(orAuto(o.ColorParameter, NONE), cItems));
lbC.Layout.Row = 2; lbC.Layout.Column = 3;

ok = runModal(dlg);
if ok
    o.XParameter     = noAuto(lbX.Value, AUTO);
    o.YParameter     = noAuto(lbY.Value, AUTO);
    o.ColorParameter = noAuto(lbC.Value, NONE);
end
delete(dlg);
end

function [o, ok] = pumpDialog(obj, r)
o = r.Options;
sections = cellstr(gui.SyringePump.SECTIONS);

[dlg, g] = modalShell(obj, sprintf('Syringe Pump - %s', orLabel(r)), 420, 420, [3 1]);
g.RowHeight = {40, '1x', 22};

lbl = uilabel(g, 'Text','Panel sections to show (select none for the full panel):', ...
    'WordWrap','on');
lbl.Layout.Row = 1;
lb = uilistbox(g, 'Items',sections, 'Multiselect','on');
lb.Layout.Row = 2;
lb.Value = intersect(o.Sections, sections);
note = uilabel(g, 'Text','Everything else follows the rig''s saved pump preferences.', ...
    'FontAngle','italic', 'FontSize',11);
note.Layout.Row = 3;

ok = runModal(dlg);
if ok
    v = lb.Value;
    if ischar(v), v = {v}; end
    v = reshape(cellstr(v), 1, []);
    if numel(v) == numel(sections), v = {}; end % all selected = full panel
    o.Sections = v;
end
delete(dlg);
end


% =========================================================================
% Shared scaffolding + converters
% =========================================================================
function [dlg, g] = modalShell(obj, title, W, H, dims)
% Modal dialog centered over the builder with an OK/Cancel row appended
% below the caller's content grid. runModal() blocks and reports OK.
fpos = [200 200 W H];
if ~isempty(obj.Fig) && isvalid(obj.Fig)
    hp = obj.Fig.Position;
    fpos = [hp(1)+(hp(3)-W)/2, hp(2)+(hp(4)-H)/2, W, H];
end
dlg = uifigure('Name',title, 'Position',fpos, 'WindowStyle','modal', ...
    'CloseRequestFcn', @(s,~) uiresume(s));
outer = uigridlayout(dlg, [2 1]);
outer.RowHeight = {'1x', 34};
outer.Padding = [8 8 8 8];
g = uigridlayout(outer, dims);
g.Padding = [0 0 0 0];
br = uigridlayout(outer, [1 3]);
br.Padding = [0 0 0 0];
br.ColumnWidth = {'1x', 90, 90};
uilabel(br, 'Text','');
uibutton(br, 'Text','OK', 'FontWeight','bold', ...
    'ButtonPushedFcn', @(~,~) okModal(dlg));
uibutton(br, 'Text','Cancel', 'ButtonPushedFcn', @(~,~) uiresume(dlg));
end

function okModal(dlg)
dlg.UserData = true;
uiresume(dlg);
end

function ok = runModal(dlg)
uiwait(dlg);
ok = isvalid(dlg) && isequal(dlg.UserData, true);
if isvalid(dlg)
    dlg.CloseRequestFcn = '';
end
end

function tf = snapTriggerStyle(snap)
if isempty(snap)
    tf = false(1,0);
    return
end
tf = [snap.isTrigger];
for i = 1:numel(snap)
    tf(i) = tf(i) || ~isempty(regexp(snap(i).Name, '^[~!]', 'once'));
end
end

function row = snapRow(snap, name)
row = [];
ix = find(strcmp({snap.Name}, name), 1);
if ~isempty(ix), row = snap(ix); end
end

function d = controlsToCell(controls)
d = cell(numel(controls), 4);
for i = 1:numel(controls)
    d(i,:) = {controls(i).Param, controls(i).Type, controls(i).autoCommit, controls(i).Text};
end
end

function controls = cellToControls(d, snap) %#ok<INUSD>
controls = repmat(struct('Param','','Type','auto','autoCommit',false,'Text',''), 1, 0);
for i = 1:size(d,1)
    controls(end+1) = struct('Param',d{i,1}, 'Type',d{i,2}, ...
        'autoCommit',logical(d{i,3}), 'Text',d{i,4}); %#ok<AGROW>
end
end

function d = buttonsToCell(buttons)
d = cell(numel(buttons), 2);
for i = 1:numel(buttons)
    d(i,:) = {buttons(i).Param, buttons(i).Text};
end
end

function buttons = cellToButtons(d)
buttons = repmat(struct('Param','','Text',''), 1, 0);
for i = 1:size(d,1)
    buttons(end+1) = struct('Param',d{i,1}, 'Text',d{i,2}); %#ok<AGROW>
end
end

function s = orLabel(r)
s = r.Label;
if isempty(s), s = r.Id; end
end

function v = orAuto(v, placeholder)
if isempty(v), v = placeholder; end
end

function v = clampChoice(v, items)
% A saved value that no longer names a current parameter (protocol edited
% since) falls back to the first item rather than erroring the listbox.
if ~ismember(v, items), v = items{1}; end
end

function v = noAuto(v, placeholder)
v = char(v);
if strcmp(v, placeholder), v = ''; end
end
