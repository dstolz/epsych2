function refreshModuleActionButtons(obj)
    addState = 'off';
    removeState = 'off';

    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex >= 1 && interfaceIndex <= length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(interfaceIndex);
        if obj.canEditInterfaceModules(iface)
            addState = 'on';
            moduleIndex = obj.getSelectedModuleRow();
            if moduleIndex >= 1 && moduleIndex <= length(iface.Module)
                removeState = 'on';
            end
        end
    end

    if ~isempty(obj.BtnAddModule) && isvalid(obj.BtnAddModule)
        obj.BtnAddModule.Enable = addState;
    end
    if ~isempty(obj.BtnRemoveModule) && isvalid(obj.BtnRemoveModule)
        obj.BtnRemoveModule.Enable = removeState;
    end
end