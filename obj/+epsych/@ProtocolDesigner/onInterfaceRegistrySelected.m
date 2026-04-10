function onInterfaceRegistrySelected(obj, evt)
    obj.SelectedInterfaceRow = 0;
    obj.setSelectedModuleRow(0);
    if isempty(evt.SelectedNodes)
        return
    end

    selectedNode = evt.SelectedNodes(1);
    interfaceIndex = obj.getInterfaceIndexFromTreeNode(selectedNode);
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        return
    end
    obj.SelectedInterfaceRow = interfaceIndex;
    obj.setSelectedModuleRow(obj.getModuleIndexFromTreeNode(selectedNode));
    selectedModuleRow = obj.getSelectedModuleRow();

    selectedLabel = obj.interfaceLabel(obj.Protocol.Interfaces(interfaceIndex), interfaceIndex);

    if any(strcmp(selectedLabel, obj.DropDownTargetInterface.Items))
        obj.DropDownTargetInterface.Value = selectedLabel;
        obj.onTargetInterfaceChanged();
    end
    if selectedModuleRow >= 1
        moduleValue = obj.moduleDisplayLabel(obj.Protocol.Interfaces(interfaceIndex).Module(selectedModuleRow), selectedModuleRow);
        if any(strcmp(moduleValue, obj.DropDownTargetModule.Items))
            obj.DropDownTargetModule.Value = moduleValue;
        end
    end
    if any(strcmp(selectedLabel, obj.DropDownInterfaceFilter.Items))
        obj.DropDownInterfaceFilter.Value = selectedLabel;
    end

    obj.refreshParameterTable();
    obj.refreshModuleActionButtons();
    if selectedModuleRow >= 1
        obj.setStatus(sprintf('Focused on %s / %s', selectedLabel, obj.Protocol.Interfaces(interfaceIndex).Module(selectedModuleRow).Name), ...
            'Edit parameters for this module or click Add Parameter.');
    else
        obj.setStatus(sprintf('Focused on %s', selectedLabel), ...
            'Select a module in the tree or add a module if this interface allows it.');
    end
end