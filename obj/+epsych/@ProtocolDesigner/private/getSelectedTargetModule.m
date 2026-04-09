function module = getSelectedTargetModule(obj)
    module = [];
    interfaceIndex = obj.selectedTargetInterfaceIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if isempty(iface.Module) || strcmp(obj.DropDownTargetModule.Value, '<none>')
        return
    end

    moduleIndex = obj.parseIndexedLabel(obj.DropDownTargetModule.Value);
    if moduleIndex < 1 || moduleIndex > length(iface.Module)
        return
    end

    module = iface.Module(moduleIndex);
end

