function build_graphical_(obj)
% build_graphical_(obj)
% Create the widget grid for type="graphical": one (label, widget) pair per
% visible parameter inside a scrollable uigridlayout. Called at construction
% and again whenever the parameter list, its visibility, or its order changes
% (add_parameter/remove_parameter/set_parameter_visible/move_parameter),
% replacing any previous grid.
%
% Widget selection per parameter comes from resolve_style_ (explicit Styles
% entry, else "auto"). Parameters fill down each column first, so a
% single-column monitor preserves the order the parameters were supplied in.

% Replace any previous widget grid (rebuild after add/remove_parameter).
% The destroy listener must go first, otherwise deleting the old grid
% would fire ObjectBeingDestroyed and delete this monitor.
if ~isempty(obj.handle) && isvalid(obj.handle)
    if ~isempty(obj.destroyListener_)
        delete(obj.destroyListener_);
    end
    delete(obj.handle);
end

P = obj.VisibleParameters;
n = numel(P);
nCols = max(1, min(obj.LayoutColumns, max(n,1)));
nRows = max(1, ceil(n / nCols));

fontSize = obj.FontSize;
if isempty(fontSize), fontSize = 12; end

try
    g = uigridlayout(obj.Parent);
catch ME
    error('gui:Parameter_Monitor:UIFigureRequired', ...
        'type="graphical" requires a uifigure-based parent: %s', ME.message);
end
g.Scrollable = 'on';
g.Padding = [8 6 8 6];
g.RowSpacing = 4;
g.ColumnSpacing = 8;

switch obj.LabelPosition
    case "left"
        g.ColumnWidth = repmat({'fit','1x'},1,nCols);
        g.RowHeight = repmat({'fit'},1,nRows);
    case "above"
        g.ColumnWidth = repmat({'1x'},1,nCols);
        g.RowHeight = repmat({'fit'},1,2*nRows);
    case "none"
        g.ColumnWidth = repmat({'1x'},1,nCols);
        g.RowHeight = repmat({'fit'},1,nRows);
end

W = repmat(struct('Parameter',[],'Style',"label",'ValueHandle',[], ...
    'LabelHandle',[],'CellHandle',[],'LastValue',[],'LastText',"", ...
    'HighlightOn',false), 1, n);

for i = 1:n
    p = P(i);
    col = ceil(i / nRows); % fill down each column first
    row = i - (col-1)*nRows;

    style = obj.resolve_style_(p);

    tooltip = string(p.Name);
    if strlength(p.Description) > 0
        tooltip = sprintf('%s: %s', p.Name, p.Description);
    end

    hLabel = [];
    if obj.LabelPosition ~= "none"
        hLabel = uilabel(g);
        hLabel.Text = p.Name;
        hLabel.FontSize = fontSize;
        hLabel.Tooltip = tooltip;
        if obj.LabelPosition == "left"
            hLabel.HorizontalAlignment = 'right';
            hLabel.Layout.Row = row;
            hLabel.Layout.Column = 2*col - 1;
        else
            hLabel.HorizontalAlignment = 'left';
            hLabel.Layout.Row = 2*row - 1;
            hLabel.Layout.Column = col;
        end
    end

    switch style
        case "lamp"
            % A bare uilamp stretches to fill its grid cell; nest it in a
            % fixed-size cell so all lamps render at a consistent size.
            wrap = uigridlayout(g,[1 2]);
            wrap.ColumnWidth = {20,'1x'};
            wrap.RowHeight = {20};
            wrap.Padding = [0 0 0 0];
            hVal = uilamp(wrap);
            hVal.Color = obj.LampOffColor;
            hVal.Layout.Row = 1;
            hVal.Layout.Column = 1;
            hCell = wrap;

        case "gauge"
            hVal = uigauge(g,'semicircular');
            hVal.Limits = [p.Min p.Max];
            hVal.FontSize = max(8, fontSize-3);
            hCell = hVal;

        otherwise % "label"
            hVal = uilabel(g);
            hVal.Text = '';
            hVal.FontSize = fontSize;
            hVal.FontWeight = 'bold';
            hVal.HorizontalAlignment = 'left';
            hCell = hVal;
    end

    hVal.Tooltip = tooltip;

    switch obj.LabelPosition
        case "left"
            hCell.Layout.Row = row;
            hCell.Layout.Column = 2*col;
        case "above"
            hCell.Layout.Row = 2*row;
            hCell.Layout.Column = col;
        case "none"
            hCell.Layout.Row = row;
            hCell.Layout.Column = col;
    end

    W(i).Parameter = p;
    W(i).Style = style;
    W(i).ValueHandle = hVal;
    W(i).LabelHandle = hLabel;
    W(i).CellHandle = hCell;
end

obj.Widgets = W;
obj.handle = g;
obj.suppressHighlight_ = true;

% widgets are new objects, so the shared right-click menu must be re-attached
obj.attach_context_menu_();

% re-arm self-deletion on the replacement grid
obj.destroyListener_ = listener(g,'ObjectBeingDestroyed',@(~,~) delete(obj));

end
