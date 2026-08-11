function onOpenCompiledPreviewDialog(obj)
% onOpenCompiledPreviewDialog(obj)
% Open the compiled trial preview dialog and compile into it.
% Raises and recompiles into the dialog when it is already open.
    [dialog, isNew] = obj.openToolDialog('PreviewFigure', 'Compiled Preview', [1100 720]);
    if isNew
        obj.buildPreviewTab(dialog);
    end

    obj.onCompile(dialog);
end
