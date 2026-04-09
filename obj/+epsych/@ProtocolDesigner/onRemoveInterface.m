function onRemoveInterface(obj)
    interfaceIndex = obj.selectedTargetInterfaceIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.LabelStatus.Text = 'Select an interface to remove';
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if ~strcmp(questdlg(sprintf('Remove interface %s?', char(iface.Type)), ...
            'Remove Interface', 'Remove', 'Cancel', 'Cancel'), 'Remove')
        return
    end

    obj.Protocol.removeInterface(interfaceIndex);
    obj.refreshParameterTab();
    obj.LabelStatus.Text = sprintf('Removed interface %s', char(iface.Type));
end

