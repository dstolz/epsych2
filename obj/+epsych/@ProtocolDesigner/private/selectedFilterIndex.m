function idx = selectedFilterIndex(obj)
    value = obj.DropDownInterfaceFilter.Value;
    if strcmp(value, 'All Interfaces')
        idx = 0;
        return
    end

    idx = obj.parseIndexedLabel(value);
end

