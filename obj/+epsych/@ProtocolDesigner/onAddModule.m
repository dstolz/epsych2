function onAddModule(obj)
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.LabelStatus.Text = 'Select an interface before adding a module';
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if ~obj.canEditInterfaceModules(iface)
        obj.LabelStatus.Text = sprintf('Modules for %s are managed by the interface itself', char(iface.Type));
        return
    end

    defaultName = obj.getUniqueModuleText(iface, sprintf('Module%d', length(iface.Module) + 1), 'Name');
    defaultLabel = obj.getUniqueModuleText(iface, defaultName, 'Label');
    answer = inputdlg({'Module Name', 'Module Label'}, 'Add Module', 1, {defaultName, defaultLabel});
    if isempty(answer)
        obj.LabelStatus.Text = sprintf('Add module cancelled for %s', char(iface.Type));
        return
    end

    requestedName = strtrim(answer{1});
    requestedLabel = strtrim(answer{2});
    if isempty(requestedName)
        requestedName = defaultName;
    end
    if isempty(requestedLabel)
        requestedLabel = requestedName;
    end

    moduleName = obj.getUniqueModuleText(iface, requestedName, 'Name');
    moduleLabel = obj.getUniqueModuleText(iface, requestedLabel, 'Label');
    newModule = hw.Module(iface, moduleLabel, moduleName, uint8(length(iface.Module) + 1));

    modules = iface.Module;
    modules(end + 1) = newModule;
    obj.replaceInterfaceModules(iface, modules);

    obj.SelectedInterfaceRow = interfaceIndex;
    obj.setSelectedModuleRow(length(modules));
    obj.refreshParameterTab();
    obj.LabelStatus.Text = sprintf('Added module %s to %s', moduleName, char(iface.Type));
end