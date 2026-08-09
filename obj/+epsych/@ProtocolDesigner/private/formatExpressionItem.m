function itemText = formatExpressionItem(~, item)
% itemText = formatExpressionItem(~, item)
% Label one selectable item of a String or StimType parameter for the status line.
%
% Parameters:
%	item	- One element of the parameter's Values item list.
%
% Returns:
%	itemText	- Compact display label for that item.
    if isa(item, 'stimgen.StimType')
        itemText = char(string(item.DisplayName));
    else
        itemText = char(string(item));
    end

    if isempty(itemText)
        itemText = '<unnamed>';
    end
end
