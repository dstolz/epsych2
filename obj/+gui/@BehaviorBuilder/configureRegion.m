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
    case 'Notes'
        [o, ok] = notesDialog(obj, r);
    case 'SyringePump'
        [o, ok] = pumpDialog(obj, r);
    case 'OnlinePlot'
        [o, ok] = onlinePlotDialog(obj, r, snap);
    case 'BufferPlot'
        [o, ok] = bufferPlotDialog(obj, r, snap);
    case 'SessionGate'
        [o, ok] = oneFieldDialog(obj, r, 'Text', 'Button label');
    case 'PhaseSelector'
        [o, ok] = oneFieldDialog(obj, r, 'PhasePath', 'Phase folder (blank = ask on first use)');
    case 'StatusBar'
        [o, ok] = oneFieldDialog(obj, r, 'InitialText', 'Initial text');
    case 'FilenameField'
        [o, ok] = oneFieldDialog(obj, r, 'DefaultFilename', 'Default filename (.mat)');
    otherwise
        % A discovered component: its options come from its own spec, on
        % the shared form. A spec with no options has nothing to configure.
        [o, ok] = specDialog(obj, r);
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

function [o, ok] = notesDialog(obj, r)
% Stamp format, the starting Editable state, and whether the region is the
% whole pad or just a button that opens it in a window.
o = r.Options;

stamps = {'elapsed','clock','none'};
labels = {'Trial + elapsed session time', 'Trial + wall clock', 'Trial number only'};

[dlg, g] = modalShell(obj, sprintf('Session Notes - %s', orLabel(r)), 440, 300, [6 2]);
g.RowHeight = {22, 22, 22, 22, 22, '1x'};
g.ColumnWidth = {130, '1x'};

lbl = uilabel(g, 'Text','Stamp each note with:');
lbl.Layout.Row = 1; lbl.Layout.Column = 1;
dd = uidropdown(g, 'Items',labels, 'ItemsData',stamps, ...
    'Value',clampChoice(o.TimeStamp, stamps));
dd.Layout.Row = 1; dd.Layout.Column = 2;

cbEdit = uicheckbox(g, 'Text','Log box hand-editable from the start', ...
    'Value',logical(o.Editable));
cbEdit.Layout.Row = 2; cbEdit.Layout.Column = [1 2];

cbBtn = uicheckbox(g, 'Text','Button only (the notes open in their own window)', ...
    'Value',logical(o.ButtonOnly));
cbBtn.Layout.Row = 3; cbBtn.Layout.Column = [1 2];

lblT = uilabel(g, 'Text','Button label:');
lblT.Layout.Row = 4; lblT.Layout.Column = 1;
ef = uieditfield(g, 'text', 'Value',char(string(o.Text)));
ef.Layout.Row = 4; ef.Layout.Column = 2;

note = uilabel(g, 'Text',['Notes are saved with the data either way, in the Info ' ...
    'variable, and journaled as they are typed.'], ...
    'WordWrap','on', 'FontAngle','italic', 'FontSize',11);
note.Layout.Row = [5 6]; note.Layout.Column = [1 2];

% The label only means anything in the button form, and the Editable state
% belongs to the log box the button form does not have.
cbBtn.ValueChangedFcn = @(s,~) syncEnable(s.Value);
syncEnable(cbBtn.Value);

ok = runModal(dlg);
if ok
    o.TimeStamp  = dd.Value;
    o.Editable   = cbEdit.Value;
    o.ButtonOnly = cbBtn.Value;
    o.Text       = strtrim(char(ef.Value));
    if isempty(o.Text), o.Text = 'Notes'; end   % an unlabelled button says nothing
end
delete(dlg);

    function syncEnable(buttonOnly)
        ef.Enable     = matlab.lang.OnOffSwitchState(buttonOnly);
        lblT.Enable   = matlab.lang.OnOffSwitchState(buttonOnly);
        cbEdit.Enable = matlab.lang.OnOffSwitchState(~buttonOnly);
    end
end


function [o, ok] = pumpDialog(obj, r)
o = r.Options;
sections = cellstr(gui.components.SyringePump.SECTIONS);

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
function [o, ok] = oneFieldDialog(obj, r, field, label)
% One text option, through the shared promptFields form. Cancel leaves the
% region's options untouched, which is what makes the caller's isNew removal
% the only thing that undoes a placement.
o = r.Options;
f = struct('Name',field, 'Label',label, 'Kind','text', 'Items',{{}}, ...
    'Value',o.(field));
out = gui.BehaviorBuilder.promptFields(obj.Fig, ...
    sprintf('%s - %s', gui.BehaviorBuilder.catalogEntry(r.Type).Display, orLabel(r)), f);
ok = ~isempty(out);
if ok, o.(field) = char(string(out.(field))); end
end


function [o, ok] = specDialog(obj, r)
% Every option a discovered component's gui.ComponentSpec declares, on the
% shared promptFields form. This is what puts a component added to the
% gui.components package behind a working Configure... button with no
% dialog written for it.
%
% The form renders text, numeric, logical and choice. A parameter picker or
% a list is shown as text: a single name, or names separated by commas,
% which is what a build method would write anyway.
o = r.Options;
s = gui.ComponentSpec.forClass(gui.BehaviorBuilder.classForType_(r.Type));
fields = struct('Name',{}, 'Label',{}, 'Kind',{}, 'Items',{}, 'Value',{});
for k = 1:numel(s.options)
    op = s.options(k);
    f  = op.toPromptField();
    if isfield(o, f.Name), f.Value = o.(f.Name); end
    if strcmp(f.Kind, 'text')
        f.Value = asFormText(f.Value);
    elseif strcmp(f.Kind, 'numeric') && ~isnumeric(f.Value)
        f.Value = [];
    elseif strcmp(f.Kind, 'logical')
        f.Value = logical(f.Value);
        if isempty(f.Value), f.Value = false; end
    end
    fields(end+1) = f; %#ok<AGROW>
end
if isempty(fields)
    ok = true;
    return
end

out = gui.BehaviorBuilder.promptFields(obj.Fig, ...
    sprintf('%s - %s', s.label, orLabel(r)), fields);
ok = ~isempty(out);
if ~ok, return; end

for k = 1:numel(fields)
    nm = fields(k).Name;
    v  = out.(nm);
    op = s.options(strcmp({s.options.name}, nm));
    if strcmp(fields(k).Kind, 'text')
        v = fromFormText(v, op);
    end
    o.(nm) = v;
end
end

function t = asFormText(v)
% Display form for a value the shared form can only show as text.
if ischar(v) || (isstring(v) && isscalar(v))
    t = char(v);
elseif isstring(v) || iscellstr(v) %#ok<ISCLSTR>
    t = strjoin(cellstr(v), ', ');
elseif isempty(v)
    t = '';
else
    t = mat2str(v);
end
end

function v = fromFormText(t, op)
% Take a text field back to the shape its option wants: a list splits on
% commas, a scalar stays text. Nothing is evaluated -- this dialog edits a
% file that becomes source, and a cell that could eval anything is a trap.
t = strtrim(char(string(t)));
if op.isList || any(strcmp(op.inputType, {'paramlist'}))
    if isempty(t)
        v = {};
    else
        v = strtrim(strsplit(t, ','));
    end
else
    v = t;
end
end

function [o, ok] = bufferPlotDialog(obj, r, snap)
% Buffer parameters from the snapshot, plus the sample rate and the two
% display choices worth fixing at design time. Leaving the list EMPTY is a
% real answer -- gui.components.BufferPlot then plots the session's own buffers -- so
% unlike the online plot there is nothing here to insist on.
o = r.Options;
buffers = {};
if ~isempty(snap)
    buffers = {snap(strcmp({snap.Type}, 'Buffer')).Name};
end

[dlg, g] = modalShell(obj, sprintf('Buffer Plot - %s', orLabel(r)), 460, 420, [5 1]);
g.RowHeight = {34, '1x', 34, 34, 34};

lbl = uilabel(g, 'Text','Buffers to plot (none = every buffer this protocol has):', ...
    'WordWrap','on');
lbl.Layout.Row = 1;
lb = uilistbox(g, 'Items',buffers, 'Multiselect','on');
lb.Layout.Row = 2;
if isempty(buffers)
    lb.Enable = 'off';
else
    lb.Value = intersect(o.Buffers, buffers);
end

rateRow = uigridlayout(g, [1 2]);
rateRow.Layout.Row = 3;
rateRow.ColumnWidth = {'fit','1x'};
rateRow.Padding = [0 0 0 0];
uilabel(rateRow, 'Text','Sample rate (Hz), 0 = plot samples:');
rateField = uieditfield(rateRow, 'numeric', 'Value', o.SampleRate, 'Limits',[0 Inf]);

layoutRow = uigridlayout(g, [1 2]);
layoutRow.Layout.Row = 4;
layoutRow.ColumnWidth = {'fit','1x'};
layoutRow.Padding = [0 0 0 0];
uilabel(layoutRow, 'Text','Layout:');
layoutDD = uidropdown(layoutRow, 'Items',{'overlay','stacked'}, 'Value',o.Layout);

trialRow = uigridlayout(g, [1 2]);
trialRow.Layout.Row = 5;
trialRow.ColumnWidth = {'fit','1x'};
trialRow.Padding = [0 0 0 0];
uilabel(trialRow, 'Text','Trials shown:');
trialField = uieditfield(trialRow, 'numeric', 'Value',o.NumTrialsShown, ...
    'Limits',[1 50], 'RoundFractionalValues','on');

ok = runModal(dlg);
if ok
    % With no snapshot buffers the listbox was disabled and shows nothing:
    % the operator answered the OTHER fields, and a stored Buffers list
    % (written against the real protocol, edited here in degraded mode) must
    % survive, not be wiped by a dialog that could not display it.
    if ~isempty(buffers)
        picked = lb.Value;
        if ischar(picked), picked = {picked}; end
        o.Buffers = reshape(cellstr(picked), 1, []);
    end
    o.SampleRate = rateField.Value;
    o.Layout = layoutDD.Value;
    o.NumTrialsShown = trialField.Value;
end
delete(dlg);
end


function [o, ok] = onlinePlotDialog(obj, r, snap)
% Read parameters from the snapshot, plus a free-text line for anything the
% snapshot cannot show. Bitmask BANKS are the reason that line exists: their
% '~BMid-<bank>' parameters are invisible, so they never reach a snapshot,
% and a bank name is exactly what gui.components.OnlinePlot most usefully plots.
o = r.Options;
readable = {};
if ~isempty(snap)
    isRead = strcmp({snap.Access}, 'Read');
    readable = {snap(isRead & ~snapTriggerStyle(snap)).Name};
end

[dlg, g] = modalShell(obj, sprintf('Online Plot - %s', orLabel(r)), 460, 420, [4 1]);
g.RowHeight = {34, '1x', 34, 22};

lbl = uilabel(g, 'Text','Read parameters to trace:', 'WordWrap','on');
lbl.Layout.Row = 1;
lb = uilistbox(g, 'Items',readable, 'Multiselect','on');
lb.Layout.Row = 2;
if isempty(readable), lb.Enable = 'off'; end
lb.Value = intersect(o.Source, readable);

ef = uieditfield(g, 'Value', strjoin(setdiff(o.Source, readable), ', '));
ef.Layout.Row = 3;
ef.Placeholder = 'Bitmask bank names, comma separated';
note = uilabel(g, 'Text','A bank plots one trace per named bit.', ...
    'FontAngle','italic', 'FontSize',11);
note.Layout.Row = 4;

ok = runModal(dlg);
if ok
    picked = lb.Value;
    if ischar(picked), picked = {picked}; end
    typed = strtrim(strsplit(ef.Value, ','));
    typed = typed(~cellfun(@isempty, typed));
    o.Source = reshape(unique([cellstr(picked), typed], 'stable'), 1, []);
end
end


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
