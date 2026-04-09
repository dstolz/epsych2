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
        items{moduleIdx} = sprintf('%d: %s', moduleIdx, iface.Module(moduleIdx).Name);
    end
end

