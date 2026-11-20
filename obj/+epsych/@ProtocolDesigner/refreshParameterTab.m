function refreshParameterTab(obj)
    obj.refreshExpressionValues();
    obj.refreshInterfaceBuilder();
    obj.refreshInterfaceControls();
    obj.refreshInterfaceSummary();
    obj.refreshParameterTable();
    obj.refreshModuleActionButtons();
    obj.refreshTransferPreview();  % no-op unless the Copy or Move dialog is open
    obj.refreshFindReplacePreview();  % no-op unless Find and Replace is open; its plan holds parameter handles
end

