function interfaceIndex = getSelectedInterfaceRowIndex(obj)
    interfaceIndex = obj.SelectedInterfaceRow;
    if interfaceIndex >= 1 && interfaceIndex <= length(obj.Protocol.Interfaces)
        return
    end

    if ~isempty(obj.InterfaceTree) && isvalid(obj.InterfaceTree) && ~isempty(obj.InterfaceTree.SelectedNodes)
        interfaceIndex = obj.getInterfaceIndexFromTreeNode(obj.InterfaceTree.SelectedNodes(1));
        if interfaceIndex >= 1 && interfaceIndex <= length(obj.Protocol.Interfaces)
            return
        end
    end

    interfaceIndex = obj.selectedTargetInterfaceIndex();
end