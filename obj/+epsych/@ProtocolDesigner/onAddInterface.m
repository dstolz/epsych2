function onAddInterface(obj)
    try
        [spec, ~] = obj.getSelectedInterfaceSpec();
        existingTypes = arrayfun(@(iface) char(string(iface.Type)), obj.Protocol.Interfaces, 'UniformOutput', false);
        if any(strcmp(spec.type, existingTypes))
            obj.refreshInterfaceBuilder();
            obj.setStatus(sprintf('Interface %s already exists', spec.label), ...
                'Modify the existing interface or choose a different interface type.');
            return
        end
        options = obj.promptForInterfaceOptions(spec, struct(), 'Add Interface', 'interface');
        if isempty(options)
            obj.setStatus(sprintf('Add %s cancelled', spec.label), ...
                'Review the interface options and try Add Interface again when ready.');
            return
        end
        interface = spec.createFcn(options);
        obj.Protocol.addInterface(interface);
        newInterfaceIndex = length(obj.Protocol.Interfaces);
        obj.SelectedInterfaceRow = newInterfaceIndex;
        obj.setSelectedModuleRow(0);
        obj.refreshParameterTab();
        newLabel = obj.interfaceLabel(interface, newInterfaceIndex);
        if ~isempty(obj.InterfaceTree) && isvalid(obj.InterfaceTree) && ~isempty(obj.InterfaceTree.SelectedNodes)
            obj.onInterfaceRegistrySelected(struct('SelectedNodes', obj.InterfaceTree.SelectedNodes));
        end
        if any(strcmp(newLabel, obj.DropDownTargetInterface.Items))
            obj.DropDownTargetInterface.Value = newLabel;
            obj.onTargetInterfaceChanged();
        end
        if any(strcmp(newLabel, obj.DropDownInterfaceFilter.Items))
            obj.DropDownInterfaceFilter.Value = newLabel;
            obj.refreshParameterTable();
        end
        obj.setStatus(sprintf('Added interface %s', char(interface.Type)), ...
            'Select the interface in the tree, then add a module or review its options.');
    catch ME
        obj.setStatus(sprintf('Add interface failed: %s', ME.message), ...
            'Check the interface options and required files, then try again.');
    end
end

