function onAddInterface(obj)
% onAddInterface(obj)
% Prompt for interface settings and add the interface to the active protocol.
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
        obj.IsModified_ = true;
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

        if obj.canEditInterfaceModules(interface)
            previousModuleCount = length(interface.Module);
            obj.onAddModule();
            updatedInterface = obj.Protocol.Interfaces(newInterfaceIndex);
            if length(updatedInterface.Module) > previousModuleCount
                return
            end

            obj.setStatus(sprintf('Added interface %s', char(interface.Type)), ...
                'Add a module when ready or review the interface options first.');
            return
        end

        obj.setStatus(sprintf('Added interface %s', char(interface.Type)), ...
            'Review the interface options or select it in the tree to inspect its modules.');
    catch ME
        obj.setStatus(sprintf('Add interface failed: %s', ME.message), ...
            'Check the interface options and required files, then try again.');
    end
end

