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
        preferredModule = '';
        interfaceIndex = obj.selectedTargetInterfaceIndex();
        selectedModuleRow = obj.getSelectedModuleRow();
        if selectedModuleRow >= 1 && interfaceIndex >= 1 && interfaceIndex <= length(obj.Protocol.Interfaces) ...
                && selectedModuleRow <= length(obj.Protocol.Interfaces(interfaceIndex).Module)
            preferredModule = obj.moduleDisplayLabel(obj.Protocol.Interfaces(interfaceIndex).Module(selectedModuleRow), selectedModuleRow);
        end
        if ~isempty(preferredModule) && any(strcmp(preferredModule, moduleItems))
            obj.DropDownTargetModule.Value = preferredModule;
        elseif any(strcmp(currentModule, moduleItems))
            obj.DropDownTargetModule.Value = currentModule;
        else
            obj.DropDownTargetModule.Value = moduleItems{1};
        end
    end
end

