function onOpenOptionsDialog(obj)
% onOpenOptionsDialog(obj)
% Open the Protocol Options dialog and sync it to the bound protocol.
% Raises the dialog when it is already open.
    [dialog, isNew] = obj.openToolDialog('OptionsFigure', 'Protocol Options', [800 270]);
    if ~isNew
        return
    end

    obj.buildOptionsTab(dialog);
    obj.refreshOptionsTab();
end
