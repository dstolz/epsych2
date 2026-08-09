function items = getTargetModuleItems(obj)
    items = {};
    if isempty(obj.Protocol.Interfaces)
        return
    end

    interfaceIndex = obj.selectedTargetInterfaceIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    items = cell(1, length(iface.Module));
    for moduleIdx = 1:length(iface.Module)
        items{moduleIdx} = obj.moduleDisplayLabel(iface.Module(moduleIdx), moduleIdx);
    end
end

