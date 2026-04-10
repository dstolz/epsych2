function onOpenCompiledPreviewDialog(obj)
    dialog = uifigure( ...
        'Name', 'Compiled Preview', ...
        'Position', [140 100 1100 720], ...
        'Resize', 'off');

    obj.buildPreviewTab(dialog);
    try
        obj.onCompile();
    catch ME
        obj.refreshCompiledPreview();
        obj.LabelStatus.Text = sprintf('Compile failed: %s', ME.message);
        uialert(dialog, ME.message, 'Compile Failed');
    end
end