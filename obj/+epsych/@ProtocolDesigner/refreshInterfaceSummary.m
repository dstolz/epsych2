function refreshInterfaceSummary(obj)
    lines = cell(0, 1);

    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        ifaceLabel = obj.interfaceLabel(iface, ifaceIdx);
        lines{end + 1, 1} = sprintf('%s', ifaceLabel); %#ok<AGROW>

        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            lines{end + 1, 1} = sprintf('  Module %d: %s (%d params)', ...
                moduleIdx, module.Name, length(module.Parameters)); %#ok<AGROW>
        end
    end

    if isempty(lines)
        lines = {'No interfaces available.'};
    end

    obj.TextAreaInterfaceSummary.Value = lines;
end

