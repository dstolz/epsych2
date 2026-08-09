function onSaveAs(obj)
% onSaveAs(obj)
% Prompt for a new protocol file name and save the current protocol.
    startPath = obj.getProtocolFileDialogStartPath('*.eprot');
    [fileName, folder] = uiputfile( ...
        {'*.eprot', 'Protocol MAT File (*.eprot)'; '*.json', 'Protocol JSON File (*.json)'}, ...
        'Save Protocol As', startPath);
    if isequal(fileName, 0)
        return
    end

    fullPath = fullfile(folder, fileName);
    obj.Protocol.save(fullPath);
    obj.CurrentProtocolPath = fullPath;
    obj.IsModified_ = false;
    obj.setLastProtocolFilePath(fullPath);
    obj.setLastBrowseDirectory(folder);
    obj.addRecentProtocolPath(fullPath);
    obj.refreshRecentProtocolMenu();
    ver = obj.Protocol.meta.protocolVersion;
    obj.Figure.Name = sprintf('Protocol Designer  [%s]', ver);
    obj.setStatus(sprintf('Saved protocol to %s', fileName), ...
        'Ctrl+S now saves directly to the current file; use Ctrl+Shift+S to save as a new file.');
end