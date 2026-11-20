function refreshInterfaceControls(obj)
% refreshInterfaceControls(obj)
% Rebuild the Filter and Add To Interface dropdowns from the protocol's interfaces.
%
% Each dropdown keeps showing the INTERFACE it was showing, not the text it was
% showing: labels lead with their position, so removing an earlier interface
% renames the survivors (see interfaceIndexForLabel). When that interface is
% the one that went, the filter widens to All Interfaces (and Color By goes
% with it, as onInterfaceFilterChanged would have set it) and the target
% moves to the interface now selected.
    interfaceItems = obj.getInterfaceItems();

    filterItems = [{'All Interfaces'}, interfaceItems];
    previousFilter = '';
    if ~isempty(obj.DropDownInterfaceFilter.Items)
        previousFilter = obj.DropDownInterfaceFilter.Value;
    end
    filterIndex = obj.interfaceIndexForLabel(previousFilter);
    obj.DropDownInterfaceFilter.Items = filterItems;
    if filterIndex >= 1
        obj.DropDownInterfaceFilter.Value = interfaceItems{filterIndex};
    else
        obj.DropDownInterfaceFilter.Value = filterItems{1};
        if filterIndex < 0
            obj.DropDownColorBy.Value = 'Interface';
        end
    end

    previousTarget = '';
    if ~isempty(obj.DropDownTargetInterface.Items)
        previousTarget = obj.DropDownTargetInterface.Value;
    end
    targetIndex = obj.interfaceIndexForLabel(previousTarget);
    if isempty(interfaceItems)
        obj.DropDownTargetInterface.Items = {'<none>'};
        obj.DropDownTargetInterface.Value = '<none>';
    else
        obj.DropDownTargetInterface.Items = interfaceItems;
        if targetIndex < 1
            targetIndex = min(max(obj.SelectedInterfaceRow, 1), numel(interfaceItems));
        end
        obj.DropDownTargetInterface.Value = interfaceItems{targetIndex};
    end

    if obj.selectedTargetInterfaceIndex() ~= obj.SelectedInterfaceRow
        obj.setSelectedModuleRow(0);
    end

    obj.refreshTargetModuleControls();
end
