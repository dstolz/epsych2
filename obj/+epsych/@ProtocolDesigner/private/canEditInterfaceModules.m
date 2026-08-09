function tf = canEditInterfaceModules(~, iface)
    tf = isa(iface, 'hw.Software') || ismethod(iface, 'setModules') || ismethod(iface, 'set_module');
end