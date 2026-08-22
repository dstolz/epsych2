function reorderTraces(obj,varargin)
% reorderTraces(obj)
% Let the operator rearrange the y-axis order, then apply it.
%
% A small modal window listing the traces top-of-axes first, with Move Up /
% Move Down. The list is shown in AXIS order rather than data order -- the
% operator is rearranging what they see, so the top of the list is the top of
% the plot -- and reversed back before it reaches setTraceOrder, which works
% bottom-first like yPositions.
%
% Cancelling changes nothing. OK routes through setTraceOrder, the same entry
% a script uses, so colours and widths follow their traces.
%
% NO NESTED FUNCTIONS, and the window is deleted explicitly on every path.
% A nested callback handle keeps its parent workspace alive for as long as
% the figure holds it, and that workspace held the onCleanup that was
% supposed to delete the figure -- a reference cycle in which neither is ever
% released. Cancelling therefore leaked an invisible modal window, and the
% NEXT Reorder Traces... blocked in uiwait forever. The accept path only
% escaped because it deleted the figure by hand.
%
% See also: gui.OnlinePlot.setTraceOrder, gui.OnlinePlot.selectTraces

names = obj.traceNames;
if numel(names) < 2
    vprintf(1,'gui.OnlinePlot: nothing to reorder')
    return
end

items = fliplr(names); % top of the axes first

gui.PopOut.setAlwaysOnTop(obj.figH,false);
restore = onCleanup(@() gui.PopOut.setAlwaysOnTop(obj.figH,obj.stayOnTop));

fig = uifigure('Name','Reorder Traces','Visible','off', ...
    'WindowStyle','modal','Resize','off');
fig.Position(3:4) = [300 360];
movegui(fig,'center');

newItems = {};
try
    g = uigridlayout(fig,[2 3]);
    g.RowHeight = {'1x',30};
    g.ColumnWidth = {'1x',80,80};

    lb = uilistbox(g,'Items',items,'Value',items{1},'Multiselect','off');
    lb.Layout.Row = 1; lb.Layout.Column = [1 3];

    up = uibutton(g,'Text','Move Up');
    up.Layout.Row = 2; up.Layout.Column = 1;
    dn = uibutton(g,'Text','Move Down');
    dn.Layout.Row = 2; dn.Layout.Column = 2;
    okB = uibutton(g,'Text','OK');
    okB.Layout.Row = 2; okB.Layout.Column = 3;

    setappdata(fig,'ReorderAccepted',false);
    up.ButtonPushedFcn  = @(~,~) localMove(lb,-1);
    dn.ButtonPushedFcn  = @(~,~) localMove(lb,+1);
    okB.ButtonPushedFcn = @(~,~) localAccept(fig);
    fig.CloseRequestFcn = @(~,~) uiresume(fig);

    fig.Visible = 'on'; % the signal that the dialog is ready
    uiwait(fig);

    if isvalid(fig) && getappdata(fig,'ReorderAccepted')
        newItems = lb.Items;
    end
catch ME
    vprintf(0,1,ME)
end

if isvalid(fig), delete(fig); end

if isempty(newItems) || isequal(newItems,items), return; end
obj.setTraceOrder(fliplr(newItems)); % back to bottom-first
end


function localAccept(fig)
setappdata(fig,'ReorderAccepted',true);
uiresume(fig);
end


function localMove(lb,step)
% Shift the selected item one place, keeping it selected.
items = lb.Items;
i = find(strcmp(items,lb.Value),1);
if isempty(i), return; end
j = i + step;
if j < 1 || j > numel(items), return; end
items([i j]) = items([j i]);
lb.Items = items;
lb.Value = items{j};
end
