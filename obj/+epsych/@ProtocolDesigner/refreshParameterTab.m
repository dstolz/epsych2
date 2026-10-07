function refreshParameterTab(obj)
    obj.refreshExpressionValues();
    obj.refreshInterfaceBuilder();
    obj.refreshInterfaceControls();
    obj.refreshInterfaceSummary();
    obj.refreshParameterTable();
    obj.refreshModuleActionButtons();
    obj.refreshTransferPreview();  % no-op unless the Copy or Move dialog is open
end

