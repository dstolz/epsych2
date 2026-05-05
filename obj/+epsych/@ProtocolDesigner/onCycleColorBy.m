function onCycleColorBy(obj)
% onCycleColorBy(obj)
% Cycle the parameter table color mode through Type, Interface, and Pair.
    if isempty(obj.DropDownColorBy) || ~isvalid(obj.DropDownColorBy)
        return
    end

    items = cellstr(obj.DropDownColorBy.Items);
    currentIndex = find(strcmp(items, obj.DropDownColorBy.Value), 1);
    if isempty(currentIndex)
        currentIndex = 0;
    end

    nextIndex = mod(currentIndex, numel(items)) + 1;
    obj.DropDownColorBy.Value = items{nextIndex};
    obj.refreshParameterTable();
    obj.setStatus(sprintf('Color-coded by %s', items{nextIndex}), ...
        'Use the Color By dropdown or Ctrl+Shift+Y to cycle the current color mode.');
end