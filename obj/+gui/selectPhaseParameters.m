function [include, edits] = selectPhaseParameters(rows, options)
% [include, edits] = gui.selectPhaseParameters(rows, Name=Value)
% Modal dialog asking the operator which of a phase's parameters to load, and
% letting them load a different value than the phase holds for some of them.
%
% gui.components.PhaseSelector opens it from its Parameters... button (the
% answer is kept and applied when Load is pressed) and from Load itself when
% SelectParametersOnLoad is on. One row per parameter the phase targets, each
% with a checkbox: a checked parameter loads, an unchecked one is left
% exactly as the session has it -- value, range, and levels (see
% epsych.Runtime.readParameters' Exclude). Every box starts checked unless
% Include says otherwise, so accepting the dialog unchanged is an ordinary
% full load.
%
% The New cell is editable on rows whose Editable is true (shaded): typing a
% value there loads that value instead of the phase's, for this load only --
% the phase file is never changed (readParameters' Override). What was typed
% is checked by ValidateFcn as it is entered, and a refused edit is put back
% with the reason in the status line. Clearing the cell returns to the
% phase's value. Editing a row checks it, since a value typed into a row that
% will not load would go nowhere.
%
% Only the rows the phase would change are listed at first; "Show unchanged"
% lists the rest, greyed. A hidden row keeps its check state and any edit, and
% loading a parameter the phase does not change is a no-op either way, which
% is why hiding them is safe. When nothing changes, every row is shown.
%
% Parameters
%   rows - table, one row per parameter, with string variables Parameter,
%          Current, New, Unit, Changes (what else differs: range, levels,
%          expression, ...) and Module, and a logical ValueChanged (the value
%          itself would change). Optional: logical Editable (default false)
%          and string EditNote (why a row is not editable, shown when an edit
%          is refused). Description is accepted and not shown. A row changes
%          something when ValueChanged is true or Changes is non-empty.
%
% Name=Value
%   Include     - initial check state, one logical per row. Default all true.
%   Edits       - initial edited New values, one string per row; missing
%                 where the phase's value stands. Default all missing.
%   ValidateFcn - @(k, text) -> [ok, message, text]: whether text is a value
%                 row k can take, why not, and the text to show for it
%                 (normalized). Default accepts nothing, so a caller that
%                 marks rows Editable must supply it.
%   PhaseName   - phase name for the title and header. Default "".
%   AcceptText  - accept button label. Default "Load".
%   Parent      - figure the dialog is centered on. Default [].
%
% Returns
%   include - height(rows)x1 logical, true for each parameter to load; []
%             when the operator cancelled.
%   edits   - height(rows)x1 string, the edited New value (as ValidateFcn
%             normalized it) or missing where the phase's value stands; []
%             when cancelled.
%
% Usage
%   [include, edits] = gui.selectPhaseParameters(rows, PhaseName="Phase_4C", ...
%       ValidateFcn=@(k,txt) check(k,txt), Parent=fig);
%   if isempty(include), return, end   % cancelled
%
% See also: gui.components.PhaseSelector, epsych.Runtime.readParameters,
%   epsych.Runtime.phaseValueOverridable

arguments
    rows table
    options.Include (:,1) logical = true(height(rows), 1)
    options.Edits (:,1) string = repmat(string(missing), height(rows), 1)
    options.ValidateFcn function_handle = @(k, text) deal(false, 'This value cannot be edited.', "")
    options.PhaseName (1,1) string = ""
    options.AcceptText (1,1) string = "Load"
    options.Parent = []
end

assert(numel(options.Include) == height(rows), 'gui:selectPhaseParameters:IncludeSize', ...
    'Include has %d element(s) but there are %d row(s).', numel(options.Include), height(rows));
assert(numel(options.Edits) == height(rows), 'gui:selectPhaseParameters:EditsSize', ...
    'Edits has %d element(s) but there are %d row(s).', numel(options.Edits), height(rows));

COLUMNS = {'Load', 'Parameter', 'Current', 'New', 'Unit', 'Other Changes'};
NEW_COL = 4;
EDITABLE_COLOR = [1 0.98 0.88];  % shades the New cells that can be edited
EDITED_COLOR = [0.84 0.92 1];    % and marks the ones that were
ERROR_COLOR = [0.75 0.1 0.1];

nRows = height(rows);
vars = rows.Properties.VariableNames;
editable = false(nRows, 1);
if ismember('Editable', vars)
    editable = logical(rows.Editable);
end
editNote = strings(nRows, 1);
if ismember('EditNote', vars)
    editNote = string(rows.EditNote);
end
checked = options.Include;
edits = options.Edits;
edits(~editable) = missing;   % an edit a row cannot take is not carried
baseChanged = rows.ValueChanged | strlength(rows.Changes) > 0;
nameText = localNames(rows);
shown = (1:nRows)';
result = [];

if strlength(options.PhaseName) > 0
    dlgTitle = sprintf('Load Phase: %s', options.PhaseName);
    phaseRef = sprintf('Phase "%s"', options.PhaseName);
else
    dlgTitle = 'Load Phase';
    phaseRef = 'This phase';
end
nChanged = nnz(baseChanged);
if nChanged == 0
    headerText = sprintf('%s would not change any of the %d parameter(s) it defines.', phaseRef, nRows);
else
    headerText = sprintf('%s would change %d of the %d parameter(s) it defines.', phaseRef, nChanged, nRows);
end
headerText = sprintf(['%s Uncheck a parameter to leave it as it is now. ' ...
    'Edit a shaded New value to load a different one this time; the phase file is not changed.'], headerText);

% Built hidden and shown once complete: creating the components yields, so a
% visible window could be clicked -- by an operator or a timer -- before its
% table was filled.
fig = uifigure(Name = dlgTitle, Position = local_placement_(options.Parent), Visible = 'off', ...
    WindowStyle = 'modal', WindowKeyPressFcn = @(~, evt) onKey(evt));
fig.CloseRequestFcn = @(~, ~) onCancel();

try
    grid = uigridlayout(fig, [3 6]);
    grid.RowHeight = {'fit', '1x', 'fit'};
    grid.ColumnWidth = {'fit', 'fit', 'fit', '1x', 'fit', 'fit'};
    grid.RowSpacing = 8;

    header = uilabel(grid, Text = headerText, WordWrap = 'on');
    header.Layout.Row = 1;
    header.Layout.Column = [1 6];

    tbl = uitable(grid, RowName = {}, ColumnName = COLUMNS, ...
        ColumnWidth = {50, 'auto', 'auto', 'auto', 'fit', '1x'}, ...
        ColumnEditable = [true false false true false false], ...
        CellEditCallback = @(~, evt) onEdit(evt));
    tbl.Layout.Row = 2;
    tbl.Layout.Column = [1 6];

    btnAll = uibutton(grid, Text = 'Check All', ...
        Tooltip = 'Load every listed parameter', ...
        ButtonPushedFcn = @(~, ~) setShown(true));
    btnAll.Layout.Row = 3;
    btnAll.Layout.Column = 1;

    btnNone = uibutton(grid, Text = 'Check None', ...
        Tooltip = 'Leave every listed parameter as it is', ...
        ButtonPushedFcn = @(~, ~) setShown(false));
    btnNone.Layout.Row = 3;
    btnNone.Layout.Column = 2;

    % Nothing to hide when nothing changes, so the box starts ticked and the
    % operator sees what a load would re-apply.
    showAll = uicheckbox(grid, Text = 'Show unchanged', Value = nChanged == 0, ...
        Tooltip = 'Also list the parameters this phase would not change', ...
        ValueChangedFcn = @(~, ~) refreshTable());
    showAll.Layout.Row = 3;
    showAll.Layout.Column = 3;

    status = uilabel(grid, Text = '', FontAngle = 'italic', HorizontalAlignment = 'right', ...
        WordWrap = 'on');
    status.Layout.Row = 3;
    status.Layout.Column = 4;
    statusColor = status.FontColor;

    btnCancel = uibutton(grid, Text = 'Cancel', ...
        Tooltip = 'Keep the selection as it was', ...
        ButtonPushedFcn = @(~, ~) onCancel());
    btnCancel.Layout.Row = 3;
    btnCancel.Layout.Column = 5;

    btnLoad = uibutton(grid, Text = options.AcceptText, ...
        Tooltip = 'Use the checked parameters, with any edited values; unchecked ones are left as they are', ...
        ButtonPushedFcn = @(~, ~) onLoad());
    btnLoad.Layout.Row = 3;
    btnLoad.Layout.Column = 6;

    refreshTable();
    fig.Visible = 'on';
catch ME
    % A half-built modal window would block the whole application.
    delete(fig);
    rethrow(ME);
end

% Every answer ends by deleting the window, so wait for exactly that.
% waitfor rather than uiwait: a window answered in the instant before the
% wait -- showing it yields, and a timer may run -- makes waitfor return at
% once, where uiwait yields again first and then throws on the deleted handle.
waitfor(fig);
if isempty(result)
    include = [];
    edits = [];
else
    include = result.include;
    edits = result.edits;
end


    function tf = isChange()
        % A row edited to something other than what it holds now is a change
        % even when the phase's own value is not.
        tf = baseChanged | (~ismissing(edits) & edits ~= rows.Current);
    end

    function txt = newText(k)
        txt = rows.New(k);
        if ~ismissing(edits(k))
            txt = edits(k);
        end
    end

    function refreshTable()
        % Rows edited here stay listed whatever the filter says: an edit is
        % the operator's own change, and it would be lost from view otherwise.
        if showAll.Value
            shown = (1:nRows)';
        else
            shown = find(baseChanged | ~ismissing(edits));
        end
        newCol = rows.New(shown);
        mine = ~ismissing(edits(shown));
        newCol(mine) = edits(shown(mine));
        % Variable names are the headers: a table's own names are what
        % uitable shows, whatever ColumnName said before Data arrived.
        tbl.Data = table(checked(shown), nameText(shown), rows.Current(shown), ...
            newCol, rows.Unit(shown), rows.Changes(shown), VariableNames = COLUMNS);
        restyle();
        updateStatus();
    end

    function restyle()
        removeStyle(tbl);
        changedNow = isChange();
        quiet = find(~changedNow(shown));
        if ~isempty(quiet)
            addStyle(tbl, uistyle(FontColor = [0.5 0.5 0.5]), 'row', quiet);
        end
        canEdit = find(editable(shown));
        if ~isempty(canEdit)
            addStyle(tbl, uistyle(BackgroundColor = EDITABLE_COLOR), 'cell', ...
                [canEdit, repmat(NEW_COL, numel(canEdit), 1)]);
        end
        % The New cell is bold where the value itself moves, so a row changed
        % only in its range or levels still reads at a glance.
        moved = find(rows.ValueChanged(shown) | ~ismissing(edits(shown)));
        if ~isempty(moved)
            addStyle(tbl, uistyle(FontWeight = 'bold'), 'cell', [moved, repmat(NEW_COL, numel(moved), 1)]);
        end
        edited = find(~ismissing(edits(shown)));
        if ~isempty(edited)
            addStyle(tbl, uistyle(BackgroundColor = EDITED_COLOR, FontAngle = 'italic'), 'cell', ...
                [edited, repmat(NEW_COL, numel(edited), 1)]);
        end
    end

    function onEdit(evt)
        r = evt.Indices(1);
        k = shown(r);
        if evt.Indices(2) == 1
            checked(k) = logical(evt.NewData);
            updateStatus();
            return
        end

        % The New column. Whatever happens the cell ends showing what will
        % load, so a refused edit is put back rather than left on screen.
        txt = strtrim(string(evt.NewData));
        message = '';
        if ~editable(k)
            message = sprintf('%s cannot be edited: %s.', rows.Parameter(k), editNote(k));
        elseif strlength(txt) == 0 || txt == rows.New(k)
            edits(k) = missing;
        else
            [ok, why, normalized] = options.ValidateFcn(k, txt);
            if ok && string(normalized) == rows.New(k)
                edits(k) = missing;   % typed the phase's own value another way
            elseif ok
                edits(k) = string(normalized);
                checked(k) = true;
                tbl.Data.Load(r) = true;
            else
                message = sprintf('%s: %s', rows.Parameter(k), why);
            end
        end
        tbl.Data.New(r) = newText(k);
        restyle();
        updateStatus();
        if ~isempty(message)
            status.Text = message;
            status.FontColor = ERROR_COLOR;
        end
    end

    function setShown(tf)
        checked(shown) = tf;
        refreshTable();
    end

    function updateStatus()
        status.FontColor = statusColor;
        changedNow = isChange();
        nNow = nnz(changedNow);
        kept = nnz(~checked);
        nEdited = nnz(~ismissing(edits) & checked);
        if nNow == 0
            status.Text = sprintf('%d of %d parameter(s) checked', nnz(checked), nRows);
        else
            status.Text = sprintf('Loading %d of %d change(s)', nnz(checked & changedNow), nNow);
        end
        if nEdited > 0
            status.Text = sprintf('%s; %d value(s) edited', status.Text, nEdited);
        end
        if kept > 0
            status.Text = sprintf('%s; %d left as they are', status.Text, kept);
        end
        % Loading nothing is Cancel by another name, and a load that touches
        % no parameter would still be recorded as a phase load.
        btnLoad.Enable = matlab.lang.OnOffSwitchState(any(checked));
    end

    function onKey(evt)
        if strcmp(evt.Key, 'escape')
            onCancel();
        end
    end

    function onLoad()
        if ~any(checked), return, end
        result = struct('include', checked, 'edits', edits);
        delete(fig);
    end

    function onCancel()
        result = [];
        delete(fig);
    end
end


function names = localNames(rows)
% Parameter names as listed: a name two interfaces share is qualified with
% its module, since otherwise the two rows are indistinguishable.
names = string(rows.Parameter);
if ~ismember('Module', rows.Properties.VariableNames), return, end
[u, ~, j] = unique(names);
dup = accumarray(j, 1, [numel(u) 1]) > 1;
dupRows = dup(j) & strlength(rows.Module) > 0;
names(dupRows) = names(dupRows) + " (" + string(rows.Module(dupRows)) + ")";
end


function pos = local_placement_(parent)
% Center the dialog on parent when there is one, else on screen.
w = 720;
h = 420;
if ~isempty(parent) && isgraphics(parent)
    p = parent.Position;
    pos = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2, w, h];
else
    s = get(groot, 'ScreenSize');
    pos = [(s(3) - w) / 2, (s(4) - h) / 2, w, h];
end
end
