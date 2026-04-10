function refreshInterfaceControls(obj)
    interfaceItems = obj.getInterfaceItems();

    filterItems = [{'All Interfaces'}, interfaceItems];
    currentFilter = '';
    if ~isempty(obj.DropDownInterfaceFilter.Items)
        currentFilter = obj.DropDownInterfaceFilter.Value;
    end
    obj.DropDownInterfaceFilter.Items = filterItems;
    if any(strcmp(currentFilter, filterItems))
        obj.DropDownInterfaceFilter.Value = currentFilter;
    else
        obj.DropDownInterfaceFilter.Value = filterItems{1};
    end

    currentTarget = '';
    if ~isempty(obj.DropDownTargetInterface.Items)
        currentTarget = obj.DropDownTargetInterface.Value;
    end
    obj.DropDownTargetInterface.Items = interfaceItems;
    if isempty(interfaceItems)
        obj.DropDownTargetInterface.Items = {'<none>'};
        obj.DropDownTargetInterface.Value = '<none>';
    elseif any(strcmp(currentTarget, interfaceItems))
        obj.DropDownTargetInterface.Value = currentTarget;
    else
        obj.DropDownTargetInterface.Value = interfaceItems{1};
    end

    if obj.selectedTargetInterfaceIndex() ~= obj.SelectedInterfaceRow
        obj.setSelectedModuleRow(0);
    end

    obj.refreshTargetModuleControls();
end

