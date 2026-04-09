function refreshTargetModuleControls(obj)
    moduleItems = obj.getTargetModuleItems();
    currentModule = '';
    if ~isempty(obj.DropDownTargetModule.Items)
        currentModule = obj.DropDownTargetModule.Value;
    end

    if isempty(moduleItems)
        obj.DropDownTargetModule.Items = {'<none>'};
        obj.DropDownTargetModule.Value = '<none>';
    else
        obj.DropDownTargetModule.Items = moduleItems;
        if any(strcmp(currentModule, moduleItems))
            obj.DropDownTargetModule.Value = currentModule;
        else
            obj.DropDownTargetModule.Value = moduleItems{1};
        end
    end
end

