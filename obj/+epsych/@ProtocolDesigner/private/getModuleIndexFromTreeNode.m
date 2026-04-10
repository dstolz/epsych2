function moduleIndex = getModuleIndexFromTreeNode(~, node)
    moduleIndex = 0;
    currentNode = node;
    while ~isempty(currentNode)
        if isprop(currentNode, 'NodeData') && ~isempty(currentNode.NodeData) && isstruct(currentNode.NodeData) ...
                && isfield(currentNode.NodeData, 'moduleIndex')
            moduleIndex = currentNode.NodeData.moduleIndex;
            return
        end

        if isprop(currentNode, 'Parent') && isa(currentNode.Parent, 'matlab.ui.container.TreeNode')
            currentNode = currentNode.Parent;
        else
            currentNode = [];
        end
    end
end