function lay = controlColumn(parent, options)
% lay = gui.components.controlColumn(parent, Title=..., Row=..., Column=..., Rows=..., RowHeight=...)
% Titled panel containing a scrollable fixed-row-height grid, ready for a
% stack of parameter controls.
%
% This builds layout, not a component: there is nothing to register for
% teardown, since deleting the figure takes the panel with it.
% gui.BehaviorGUI.controlColumn forwards here so call sites keep reading
% uniformly with the add* family.
%
%  Title     - panel title
%  Row       - row, or [first last], in the parent grid
%  Column    - column, or [first last], in the parent grid
%  Rows      - how many fixed-height rows the inner grid has (default 20)
%  RowHeight - height of each in pixels (default 25)
%
% See also gui.BehaviorGUI.addControl, gui.BehaviorGUI.add

arguments
    parent (1,1)
    options.Title (1,:) char = ''
    options.Row = []
    options.Column = []
    options.Rows (1,1) double {mustBeInteger,mustBePositive} = 20
    options.RowHeight (1,1) double = 25
end

p = uipanel(parent, 'Title', options.Title);
if ~isempty(options.Row),    p.Layout.Row    = options.Row;    end
if ~isempty(options.Column), p.Layout.Column = options.Column; end

lay = uigridlayout(p, [options.Rows, 1]);
lay.RowHeight  = repmat({options.RowHeight}, 1, options.Rows);
lay.ColumnWidth = {'1x'};
lay.RowSpacing = 1;
lay.Padding    = [2 2 2 2];
lay.Scrollable = 'on';
end
