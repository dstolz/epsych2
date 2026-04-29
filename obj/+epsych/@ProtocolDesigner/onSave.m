function onSave(obj)
    startPath = obj.getProtocolFileDialogStartPath('*.eprot');
    [fileName, folder] = uiputfile( ...
        {'*.eprot', 'Protocol MAT File (*.eprot)'; '*.json', 'Protocol JSON File (*.json)'}, ...
        'Save Protocol', startPath);
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
        'Compile again after further edits, or close the designer if you are finished.');
end

