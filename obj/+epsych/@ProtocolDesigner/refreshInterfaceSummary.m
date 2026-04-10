function refreshInterfaceSummary(obj)
    delete(obj.InterfaceTree.Children);

    interfaceCount = length(obj.Protocol.Interfaces);
    selectedNode = [];
    selectedModuleRow = obj.getSelectedModuleRow();
    for ifaceIdx = 1:interfaceCount
        iface = obj.Protocol.Interfaces(ifaceIdx);
        moduleCount = length(iface.Module);
        parameterCount = sum(arrayfun(@(module) length(module.Parameters), iface.Module));

        ifaceNode = uitreenode(obj.InterfaceTree, ...
            'Text', sprintf('%s (%d modules, %d params)', obj.interfaceLabel(iface, ifaceIdx), moduleCount, parameterCount), ...
            'NodeData', struct('kind', 'interface', 'interfaceIndex', ifaceIdx));

        uitreenode(ifaceNode, ...
            'Text', sprintf('Type: %s', char(iface.Type)), ...
            'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx));
        uitreenode(ifaceNode, ...
            'Text', sprintf('Modules: %d', moduleCount), ...
            'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx));
        uitreenode(ifaceNode, ...
            'Text', sprintf('Parameters: %d', parameterCount), ...
            'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx));

        for moduleIdx = 1:moduleCount
            module = iface.Module(moduleIdx);
            moduleNode = uitreenode(ifaceNode, ...
                'Text', obj.moduleDisplayLabel(module, moduleIdx), ...
                'NodeData', struct('kind', 'module', 'interfaceIndex', ifaceIdx, 'moduleIndex', moduleIdx));

            uitreenode(moduleNode, ...
                'Text', sprintf('Label: %s', module.Label), ...
                'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx, 'moduleIndex', moduleIdx));
            uitreenode(moduleNode, ...
                'Text', sprintf('Index: %d', module.Index), ...
                'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx, 'moduleIndex', moduleIdx));
            uitreenode(moduleNode, ...
                'Text', sprintf('Parameters: %d', length(module.Parameters)), ...
                'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx, 'moduleIndex', moduleIdx));
            if ~isempty(module.Fs)
                uitreenode(moduleNode, ...
                    'Text', sprintf('Fs: %g', module.Fs), ...
                    'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx, 'moduleIndex', moduleIdx));
            end
            if isstruct(module.Info)
                infoFields = fieldnames(module.Info);
                for infoIdx = 1:numel(infoFields)
                    fieldName = infoFields{infoIdx};
                    fieldValue = module.Info.(fieldName);
                    uitreenode(moduleNode, ...
                        'Text', sprintf('%s: %s', fieldName, localFormatTreeValue_(fieldValue)), ...
                        'NodeData', struct('kind', 'info', 'interfaceIndex', ifaceIdx, 'moduleIndex', moduleIdx));
                end
            end
        end

        expand(ifaceNode);
        if ifaceIdx == obj.SelectedInterfaceRow && selectedModuleRow == 0
            selectedNode = ifaceNode;
        elseif ifaceIdx == obj.SelectedInterfaceRow && selectedModuleRow >= 1 && selectedModuleRow <= moduleCount
            selectedNode = ifaceNode.Children(selectedModuleRow + 3);
        end
    end

    if isempty(selectedNode) && ~isempty(obj.InterfaceTree.Children)
        selectedNode = obj.InterfaceTree.Children(1);
    end
    if ~isempty(selectedNode)
        obj.InterfaceTree.SelectedNodes = selectedNode;
    end
end

function text = localFormatTreeValue_(value)
    if ischar(value)
        text = value;
    elseif isstring(value)
        text = char(value);
    elseif isnumeric(value) || islogical(value)
        if isscalar(value)
            text = num2str(value);
        else
            text = sprintf('[%d values]', numel(value));
        end
    elseif iscell(value)
        if isempty(value)
            text = '<empty>';
        else
            firstValue = value{1};
            if ischar(firstValue) || isstring(firstValue)
                text = sprintf('%s%s', char(string(firstValue)), ternarySuffix_(numel(value) > 1, sprintf(' (+%d more)', numel(value) - 1), ''));
            else
                text = sprintf('[%d items]', numel(value));
            end
        end
    else
        text = class(value);
    end
end

function text = ternarySuffix_(condition, trueText, falseText)
    if condition
        text = trueText;
    else
        text = falseText;
    end
end

