function onSave(obj)
    startPath = obj.getProtocolFileDialogStartPath('*.eprot');
    [fileName, folder] = uiputfile('*.eprot', 'Save Protocol', startPath);
    if isequal(fileName, 0)
        return
    end

    fullPath = fullfile(folder, fileName);
    obj.Protocol.save(fullPath);
    obj.CurrentProtocolPath = fullPath;
    obj.setLastProtocolFilePath(fullPath);
    obj.setLastBrowseDirectory(folder);
    obj.addRecentProtocolPath(fullPath);
    obj.refreshRecentProtocolMenu();
    obj.setStatus(sprintf('Saved protocol to %s', fileName), ...
        'Compile again after further edits, or close the designer if you are finished.');
end

