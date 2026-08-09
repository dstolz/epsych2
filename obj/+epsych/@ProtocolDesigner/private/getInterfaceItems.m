function items = getInterfaceItems(obj)
    items = cell(1, length(obj.Protocol.Interfaces));
    for idx = 1:length(obj.Protocol.Interfaces)
        items{idx} = obj.interfaceLabel(obj.Protocol.Interfaces(idx), idx);
    end
end

