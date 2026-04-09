function parameters = getAllParameters(obj)
    parameters = hw.Parameter.empty(1, 0);
    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            if ~isempty(module.Parameters)
                parameters = [parameters, module.Parameters]; %#ok<AGROW>
            end
        end
    end
end

