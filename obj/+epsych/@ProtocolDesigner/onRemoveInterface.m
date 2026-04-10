function onRemoveInterface(obj)
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.setStatus('No interface selected for removal', 'Select an interface in the tree first.');
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if ~strcmp(questdlg(sprintf('Remove interface %s?', char(iface.Type)), ...
            'Remove Interface', 'Remove', 'Cancel', 'Cancel'), 'Remove')
        return
    end

    obj.Protocol.removeInterface(interfaceIndex);
    obj.refreshParameterTab();
    obj.setStatus(sprintf('Removed interface %s', char(iface.Type)), ...
        'Add another interface or review the remaining modules before compiling.');
end

