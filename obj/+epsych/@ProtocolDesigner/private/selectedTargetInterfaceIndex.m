function idx = selectedTargetInterfaceIndex(obj)
    value = obj.DropDownTargetInterface.Value;
    idx = obj.parseIndexedLabel(value);
end

