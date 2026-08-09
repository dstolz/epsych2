function interfaceIndex = getInterfaceIndexFromTreeNode(~, node)
    interfaceIndex = 0;
    currentNode = node;
    while ~isempty(currentNode)
        if isprop(currentNode, 'NodeData') && ~isempty(currentNode.NodeData) && isstruct(currentNode.NodeData) ...
                && isfield(currentNode.NodeData, 'interfaceIndex')
            interfaceIndex = currentNode.NodeData.interfaceIndex;
            return
        end

        if isprop(currentNode, 'Parent') && isa(currentNode.Parent, 'matlab.ui.container.TreeNode')
            currentNode = currentNode.Parent;
        else
            currentNode = [];
        end
    end
end