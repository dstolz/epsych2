function onOpenInterfaceDialog(obj)
% onOpenInterfaceDialog(obj)
% Open the Interfaces dialog and sync it to the bound protocol.
% Raises the dialog when it is already open.
    [dialog, isNew] = obj.openToolDialog('InterfaceFigure', 'Interfaces', [420 700]);
    if ~isNew
        return
    end

    obj.buildInterfaceTab(dialog);
    obj.refreshInterfaceBuilder();
    obj.refreshInterfaceSummary();
    obj.refreshModuleActionButtons();
end
