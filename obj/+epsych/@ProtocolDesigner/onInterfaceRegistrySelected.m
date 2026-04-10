function onInterfaceRegistrySelected(obj, evt)
    obj.SelectedInterfaceRow = 0;
    if isempty(evt.SelectedNodes)
        return
    end

    selectedNode = evt.SelectedNodes(1);
    interfaceIndex = obj.getInterfaceIndexFromTreeNode(selectedNode);
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        return
    end
    obj.SelectedInterfaceRow = interfaceIndex;

    selectedLabel = obj.interfaceLabel(obj.Protocol.Interfaces(interfaceIndex), interfaceIndex);

    if any(strcmp(selectedLabel, obj.DropDownTargetInterface.Items))
        obj.DropDownTargetInterface.Value = selectedLabel;
        obj.onTargetInterfaceChanged();
    end
    if any(strcmp(selectedLabel, obj.DropDownInterfaceFilter.Items))
        obj.DropDownInterfaceFilter.Value = selectedLabel;
    end

    obj.refreshParameterTable();
    obj.LabelStatus.Text = sprintf('Focused on %s', selectedLabel);
end