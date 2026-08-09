function alias = getQualifiedExpressionAlias(obj, parameter)
    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            for paramIdx = 1:length(module.Parameters)
                if isequal(module.Parameters(paramIdx), parameter)
                    alias = matlab.lang.makeValidName(sprintf('exprIface%dModule%d_%s_%s', ...
                        ifaceIdx, moduleIdx, module.Name, parameter.Name));
                    return
                end
            end
        end
    end
    alias = matlab.lang.makeValidName(sprintf('exprModule_%s_%s', parameter.Module.Name, parameter.Name));
end

