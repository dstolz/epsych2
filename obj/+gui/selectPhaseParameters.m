function include = selectPhaseParameters(rows, options)
% include = gui.selectPhaseParameters(rows, Name=Value)
% Modal dialog asking the operator which of a phase's parameters to load.
%
% gui.components.PhaseSelector opens it from Load when SelectParametersOnLoad
% is on, or from the Load button's right-click "Load Selected Parameters...".
% One row per parameter the phase targets, each with a checkbox: a checked
% parameter loads as usual, an unchecked one is left exactly as the session
% has it -- value, range, and levels (see epsych.Runtime.readParameters'
% Exclude). Every box starts checked unless Include says otherwise, so
% accepting the dialog unchanged is an ordinary full load.
%
% Only the rows the phase would change are listed at first; "Show unchanged"
% lists the rest, greyed. A hidden row keeps its check state, and loading a
% parameter the phase does not change is a no-op either way, which is why
% hiding them is safe. When nothing changes, every row is shown.
%
% Parameters
%   rows - table, one row per parameter, with string variables Parameter,
%          Description, Current, New, Unit, Changes (what else differs:
%          range, levels, expression, ...) and Module, and a logical
%          ValueChanged (the value itself would change). A row changes
%          something when ValueChanged is true or Changes is non-empty.
%
% Name=Value
%   Include   - initial check state, one logical per row. Default all true.
%   PhaseName - phase name for the title and header. Default "".
%   Parent    - figure the dialog is centered on. Default [].
%
% Returns
%   include - height(rows)x1 logical, true for each parameter to load; []
%             when the operator cancelled, in which case nothing is loaded.
%
% Usage
%   include = gui.selectPhaseParameters(rows, PhaseName="Phase_4C", Parent=fig);
%   if isempty(include), return, end   % cancelled
%
% See also: gui.components.PhaseSelector, epsych.Runtime.readParameters

arguments
    rows table
    options.Include (:,1) logical = true(height(rows), 1)
    options.PhaseName (1,1) string = ""
    options.Parent = []
end

assert(numel(options.Include) == height(rows), 'gui:selectPhaseParameters:IncludeSize', ...
    'Include has %d element(s) but there are %d row(s).', numel(options.Include), height(rows));

COLUMNS = {'Load', 'Parameter', 'Description', 'Current', 'New', 'Unit', 'Other Changes', 'Module'};

nRows = height(rows);
checked = options.Include;
changed = rows.ValueChanged | strlength(rows.Changes) > 0;
nChanged = nnz(changed);
shown = (1:nRows)';
result = [];

if strlength(options.PhaseName) > 0
    dlgTitle = sprintf('Load Phase: %s', options.PhaseName);
    phaseRef = sprintf('Phase "%s"', options.PhaseName);
else
    dlgTitle = 'Load Phase';
    phaseRef = 'This phase';
end
if nChanged == 0
    headerText = sprintf(['%s would not change any of the %d parameter(s) it defines. ' ...
        'Loading it re-applies them as they are.'], phaseRef, nRows);
else
    headerText = sprintf(['%s would change %d of the %d parameter(s) it defines. ' ...
        'Uncheck a parameter to leave it as it is now: its value, range, and levels are not touched.'], ...
        phaseRef, nChanged, nRows);
end

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
        ColumnWidth = {45, 'fit', '1x', 'fit', 'fit', 'fit', '1x', 'fit'}, ...
        ColumnEditable = [true false false false false false false false], ...
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

    status = uilabel(grid, Text = '', FontAngle = 'italic', HorizontalAlignment = 'right');
    status.Layout.Row = 3;
    status.Layout.Column = 4;

    btnCancel = uibutton(grid, Text = 'Cancel', ...
        Tooltip = 'Load nothing', ...
        ButtonPushedFcn = @(~, ~) onCancel());
    btnCancel.Layout.Row = 3;
    btnCancel.Layout.Column = 5;

    btnLoad = uibutton(grid, Text = 'Load', ...
        Tooltip = 'Load the checked parameters; unchecked ones are left as they are', ...
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
include = result;


    function refreshTable()
        if showAll.Value
            shown = (1:nRows)';
        else
            shown = find(changed);
        end
        % Variable names are the headers: a table's own names are what
        % uitable shows, whatever ColumnName said before Data arrived.
        tbl.Data = table(checked(shown), rows.Parameter(shown), rows.Description(shown), ...
            rows.Current(shown), rows.New(shown), rows.Unit(shown), rows.Changes(shown), ...
            rows.Module(shown), VariableNames = COLUMNS);

        removeStyle(tbl);
        quiet = find(~changed(shown));
        if ~isempty(quiet)
            addStyle(tbl, uistyle(FontColor = [0.5 0.5 0.5]), 'row', quiet);
        end
        % The New cell is bold where the value itself moves, so a row changed
        % only in its range or levels still reads at a glance.
        moved = find(rows.ValueChanged(shown));
        if ~isempty(moved)
            addStyle(tbl, uistyle(FontWeight = 'bold'), 'cell', [moved, repmat(5, numel(moved), 1)]);
        end
        updateStatus();
    end

    function onEdit(evt)
        k = shown(evt.Indices(1));
        checked(k) = logical(evt.NewData);
        updateStatus();
    end

    function setShown(tf)
        checked(shown) = tf;
        refreshTable();
    end

    function updateStatus()
        kept = nnz(~checked);
        if nChanged == 0
            status.Text = sprintf('%d of %d parameter(s) checked', nnz(checked), nRows);
        else
            status.Text = sprintf('Loading %d of %d change(s)', nnz(checked & changed), nChanged);
        end
        if kept > 0
            status.Text = sprintf('%s; %d parameter(s) left as they are', status.Text, kept);
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
        result = checked;
        delete(fig);
    end

    function onCancel()
        result = [];
        delete(fig);
    end
end


function pos = local_placement_(parent)
% Center the dialog on parent when there is one, else on screen.
w = 900;
h = 460;
if ~isempty(parent) && isgraphics(parent)
    p = parent.Position;
    pos = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2, w, h];
else
    s = get(groot, 'ScreenSize');
    pos = [(s(3) - w) / 2, (s(4) - h) / 2, w, h];
end
end
