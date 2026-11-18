function idx = selectFromList(items, options)
% idx = gui.selectFromList(items, Name=Value)
% Modal dialog choosing one entry from a list; [] when cancelled.
%
% A uifigure counterpart of listdlg for windows that are themselves
% uifigures. Built hidden and shown complete, and blocks in waitfor rather
% than uiwait, for the reasons gui.selectPhaseParameters gives.
%
% Name=Value
%   Title      - window title. Default "Choose".
%   Prompt     - the sentence above the list. Default "".
%   Initial    - index selected at first. Default 1.
%   AcceptText - accept button label. Default "OK".
%   Parent     - figure to center on. Default [].
%
% See also: gui.selectRegistrySubjects
arguments
    items string
    options.Title (1,1) string = "Choose"
    options.Prompt (1,1) string = ""
    options.Initial (1,1) double = 1
    options.AcceptText (1,1) string = "OK"
    options.Parent = []
end

idx = [];
if isempty(items), return, end
result = [];
w = 420;
h = 360;
if ~isempty(options.Parent) && isgraphics(options.Parent)
    p = options.Parent.Position;
    pos = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2, w, h];
else
    s = get(groot, 'ScreenSize');
    pos = [(s(3) - w) / 2, (s(4) - h) / 2, w, h];
end

fig = uifigure(Name = options.Title, Position = pos, Visible = 'off', ...
    WindowStyle = 'modal', Tag = 'SelectFromList');
fig.CloseRequestFcn = @(~, ~) onCancel();
try
    g = uigridlayout(fig, [3 3]);
    g.RowHeight = {'fit', '1x', 32};
    g.ColumnWidth = {'1x', 90, 90};
    lbl = uilabel(g, Text = options.Prompt, WordWrap = 'on');
    lbl.Layout.Row = 1;
    lbl.Layout.Column = [1 3];
    lb = uilistbox(g, Items = cellstr(items), ItemsData = num2cell(1:numel(items)), ...
        Value = max(1, min(numel(items), options.Initial)), Tag = 'SelectFromList_List', ...
        DoubleClickedFcn = @(~, ~) onAccept());
    lb.Layout.Row = 2;
    lb.Layout.Column = [1 3];
    b1 = uibutton(g, Text = 'Cancel', ButtonPushedFcn = @(~, ~) onCancel());
    b1.Layout.Row = 3;
    b1.Layout.Column = 2;
    b2 = uibutton(g, Text = options.AcceptText, Tag = 'SelectFromList_OK', ...
        ButtonPushedFcn = @(~, ~) onAccept());
    b2.Layout.Row = 3;
    b2.Layout.Column = 3;
    fig.Visible = 'on';
catch ME
    delete(fig);
    rethrow(ME);
end
waitfor(fig);
idx = result;

    function onAccept()
        result = lb.Value;
        delete(fig);
    end

    function onCancel()
        result = [];
        delete(fig);
    end
end
