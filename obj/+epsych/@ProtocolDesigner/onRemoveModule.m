function onRemoveModule(obj)
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.setStatus('No interface selected for Remove Module', 'Select an interface in the tree first.');
        return
    end

    moduleIndex = obj.getSelectedModuleRow();
    if moduleIndex < 1
        obj.setStatus('No module selected for removal', 'Select a module node in the interface tree first.');
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if moduleIndex > length(iface.Module)
        obj.setStatus('Selected module is no longer available', 'Refresh the selection and choose a valid module.');
        return
    end
    if ~obj.canEditInterfaceModules(iface)
        obj.setStatus(sprintf('Modules for %s are managed by the interface itself', char(iface.Type)), ...
            'Review the interface options instead of removing modules manually.');
        return
    end

    module = iface.Module(moduleIndex);
    removedParameterCount = length(module.Parameters);
    modules = iface.Module;
    modules(moduleIndex) = [];
    obj.replaceInterfaceModules(iface, modules);

    obj.SelectedInterfaceRow = interfaceIndex;
    obj.setSelectedModuleRow(min(moduleIndex, length(modules)));
    obj.IsModified_ = true;
    obj.refreshParameterTab();
    obj.setStatus(sprintf('Removed module %s (%d parameters)', module.Name, removedParameterCount), ...
        'Add a replacement module or compile to confirm the remaining trial set.');
end