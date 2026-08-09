function replaceInterfaceModules(~, iface, modules)
    if isa(iface, 'hw.Software')
        iface.set_module(modules);
    elseif ismethod(iface, 'setModules')
        iface.setModules(modules);
    elseif ismethod(iface, 'set_module')
        iface.set_module(modules);
    else
        error('Interface type %s does not support editing its module list in ProtocolDesigner.', char(iface.Type));
    end
end