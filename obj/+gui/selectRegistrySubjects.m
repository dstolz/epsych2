function idx = selectRegistrySubjects(T, options)
% idx = gui.selectRegistrySubjects(T, Name=Value)
% Modal dialog choosing animals from the lab's subject registry: one to link
% a roster subject to, or several to import.
%
% T is what epsych.SubjectRegistry.findSubjects returns. Rows are listed
% nearest first when NearName is given (an exact match, then names that
% contain it or are contained by it, then the rest), so the animal an operator
% means is at the top when the roster name and the registry id differ only by
% a typo or a prefix. A filter box narrows the list as it is typed. Animals
% with an endpoint are listed but not pre-selected, and say so.
%
% Name=Value
%   Title      - window title. Default "Lab Database Subjects".
%   Prompt     - the sentence above the list.
%   Multi      - true to tick several (import); false picks one (link).
%   NearName   - a roster name to sort by. Default "".
%   Exclude    - registry ids not to offer (already linked). Default none.
%   AcceptText - accept button label. Default "OK".
%   Parent     - figure to center on. Default [].
%
% Returns
%   idx - row indices into T of the chosen animals; [] when cancelled or
%         nothing was chosen.
%
% Built hidden and shown complete, and blocks in waitfor rather than uiwait,
% for the reasons gui.selectPhaseParameters gives.
%
% See also: epsych.SubjectRegistry.findSubjects, gui.SubjectManager
arguments
    T table
    options.Title (1,1) string = "Lab Database Subjects"
    options.Prompt (1,1) string = "Choose the animal in the lab database."
    options.Multi (1,1) logical = false
    options.NearName (1,1) string = ""
    options.Exclude string = strings(0, 1)
    options.AcceptText (1,1) string = "OK"
    options.Parent = []
end

idx = [];
offer = find(~ismember(T.RegistryID, options.Exclude));
offer = localOrder(T, offer, options.NearName);
result = [];
checked = false(numel(offer), 1);

fig = uifigure(Name = options.Title, Position = localPlacement(options.Parent), ...
    Visible = 'off', WindowStyle = 'modal', Tag = 'SelectRegistrySubjects', ...
    WindowKeyPressFcn = @(~, evt) onKey(evt));
fig.CloseRequestFcn = @(~, ~) onCancel();

try
    grid = uigridlayout(fig, [4 3]);
    grid.RowHeight = {'fit', 28, '1x', 32};
    grid.ColumnWidth = {'1x', 90, 90};
    grid.RowSpacing = 8;

    header = uilabel(grid, Text = options.Prompt, WordWrap = 'on');
    header.Layout.Row = 1;
    header.Layout.Column = [1 3];

    filt = uieditfield(grid, 'text', Placeholder = 'Filter by id, project...', ...
        Tag = 'SelectRegistrySubjects_Filter', ...
        ValueChangingFcn = @(~, evt) refreshTable(evt.Value), ...
        ValueChangedFcn = @(src, ~) refreshTable(src.Value));
    filt.Layout.Row = 2;
    filt.Layout.Column = [1 3];

    cols = {'', 'Lab DB ID', 'Project', 'Sex', 'Species', 'Born', 'Status'};
    tbl = uitable(grid, RowName = {}, ColumnName = cols, ...
        ColumnWidth = {30, 130, '1x', 50, 140, 90, 110}, ...
        ColumnEditable = [options.Multi false false false false false false], ...
        SelectionType = 'row', Multiselect = 'off', ...
        Tag = 'SelectRegistrySubjects_Table', ...
        CellEditCallback = @(~, evt) onTick(evt), ...
        DoubleClickedFcn = @(~, ~) onAccept());
    tbl.Layout.Row = 3;
    tbl.Layout.Column = [1 3];

    status = uilabel(grid, Text = '', FontAngle = 'italic');
    status.Layout.Row = 4;
    status.Layout.Column = 1;

    btnCancel = uibutton(grid, Text = 'Cancel', ButtonPushedFcn = @(~, ~) onCancel());
    btnCancel.Layout.Row = 4;
    btnCancel.Layout.Column = 2;
    btnOk = uibutton(grid, Text = options.AcceptText, Tag = 'SelectRegistrySubjects_OK', ...
        ButtonPushedFcn = @(~, ~) onAccept());
    btnOk.Layout.Row = 4;
    btnOk.Layout.Column = 3;

    shown = (1:numel(offer))';
    refreshTable("");
    fig.Visible = 'on';
catch ME
    delete(fig);
    rethrow(ME);
end

waitfor(fig);
if ~isempty(result)
    idx = result;
end

    function refreshTable(txt)
        txt = lower(strtrim(string(txt)));
        n = numel(offer);
        keep = true(n, 1);
        if txt ~= ""
            for k = 1:n
                r = offer(k);
                hay = lower(T.RegistryID(r) + " " + T.Project(r) + " " + T.Species(r));
                keep(k) = contains(hay, txt);
            end
        end
        shown = find(keep);
        data = cell(numel(shown), 7);
        for k = 1:numel(shown)
            r = offer(shown(k));
            data{k, 1} = checked(shown(k));
            data{k, 2} = char(T.RegistryID(r));
            data{k, 3} = char(T.Project(r));
            data{k, 4} = char(T.Sex(r));
            data{k, 5} = char(T.Species(r));
            if isnat(T.DateOfBirth(r))
                data{k, 6} = '';
            else
                data{k, 6} = char(string(T.DateOfBirth(r), 'yyyy-MM-dd'));
            end
            if T.Endpointed(r)
                data{k, 7} = 'endpoint recorded';
            else
                data{k, 7} = '';
            end
        end
        tbl.Data = data;
        if options.Multi
            status.Text = sprintf('%d shown, %d ticked', numel(shown), nnz(checked));
        else
            status.Text = sprintf('%d shown', numel(shown));
        end
    end

    function onTick(evt)
        k = shown(evt.Indices(1));
        checked(k) = logical(evt.NewData);
        status.Text = sprintf('%d shown, %d ticked', numel(shown), nnz(checked));
    end

    function onAccept()
        if options.Multi
            pick = find(checked);
        else
            sel = tbl.Selection;
            if isempty(sel)
                status.Text = 'Select an animal first.';
                return
            end
            pick = shown(sel(1));
        end
        if isempty(pick)
            status.Text = 'Tick at least one animal.';
            return
        end
        result = offer(pick);
        result = reshape(result, 1, []);
        delete(fig);
    end

    function onCancel()
        result = [];
        delete(fig);
    end

    function onKey(evt)
        if strcmp(evt.Key, 'escape')
            onCancel();
        end
    end
end

% -----------------------------------------------------------------------
function order = localOrder(T, rows, near)
% Exact name first, then names sharing a prefix/substring either way, then the
% rest by id -- the order a person scanning for "the one I mean" wants.
order = reshape(rows, [], 1);
if isempty(order), return, end
ids = T.RegistryID(order);
[~, byId] = sort(lower(ids));
order = order(byId);
if near == "", return, end
ids = lower(T.RegistryID(order));
n = lower(near);
rank = 3 * ones(numel(order), 1);
rank(contains(ids, n) | arrayfun(@(s) contains(n, s), ids)) = 2;
rank(ids == n) = 1;
[~, k] = sort(rank, 'ascend');
order = order(k);
end

function pos = localPlacement(parent)
w = 720;
h = 440;
if ~isempty(parent) && isgraphics(parent)
    p = parent.Position;
    pos = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2, w, h];
else
    s = get(groot, 'ScreenSize');
    pos = [(s(3) - w) / 2, (s(4) - h) / 2, w, h];
end
end
