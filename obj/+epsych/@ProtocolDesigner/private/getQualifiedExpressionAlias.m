function alias = getQualifiedExpressionAlias(obj, parameter)
    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            for paramIdx = 1:length(module.Parameters)
                if isequal(module.Parameters(paramIdx), parameter)
                    interfaceLabel = sprintf('%s%d', char(iface.Type), ifaceIdx);
                    moduleLabel = module.Name;
                    alias = matlab.lang.makeValidName(sprintf('%s_%s_%s', interfaceLabel, moduleLabel, parameter.Name));
                    return
                end
            end
        end
    end
    alias = matlab.lang.makeValidName(sprintf('%s_%s', parameter.Module.Name, parameter.Name));
end

