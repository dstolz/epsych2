function onRemoveModule(obj)
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.LabelStatus.Text = 'Select an interface before removing a module';
        return
    end

    moduleIndex = obj.getSelectedModuleRow();
    if moduleIndex < 1
        obj.LabelStatus.Text = 'Select a module node before removing a module';
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if moduleIndex > length(iface.Module)
        obj.LabelStatus.Text = 'Selected module is no longer available';
        return
    end
    if ~obj.canEditInterfaceModules(iface)
        obj.LabelStatus.Text = sprintf('Modules for %s are managed by the interface itself', char(iface.Type));
        return
    end

    module = iface.Module(moduleIndex);
    removedParameterCount = length(module.Parameters);
    modules = iface.Module;
    modules(moduleIndex) = [];
    obj.replaceInterfaceModules(iface, modules);

    obj.SelectedInterfaceRow = interfaceIndex;
    obj.setSelectedModuleRow(min(moduleIndex, length(modules)));
    obj.refreshParameterTab();
    obj.LabelStatus.Text = sprintf('Removed module %s (%d parameters)', module.Name, removedParameterCount);
end