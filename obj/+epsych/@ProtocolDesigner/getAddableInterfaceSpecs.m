function specs = getAddableInterfaceSpecs(obj)
    specs = obj.getAvailableInterfaceSpecs();
    if isempty(specs) || isempty(obj.Protocol.Interfaces)
        return
    end

    existingTypes = arrayfun(@(iface) char(string(iface.Type)), obj.Protocol.Interfaces, 'UniformOutput', false);
    keepMask = cellfun(@(spec) ~any(strcmp(spec.type, existingTypes)), specs);
    specs = specs(keepMask);
end