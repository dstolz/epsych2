function onSave(obj)
% onSave(obj)
% Save the current protocol and refresh recent-file state.
    if ~isempty(obj.CurrentProtocolPath) && isfile(obj.CurrentProtocolPath)
        obj.Protocol.save(obj.CurrentProtocolPath, IncrementVersion=obj.IsModified_);
        obj.IsModified_ = false;
        obj.setLastProtocolFilePath(obj.CurrentProtocolPath);
        obj.setLastBrowseDirectory(fileparts(obj.CurrentProtocolPath));
        obj.addRecentProtocolPath(obj.CurrentProtocolPath);
        obj.refreshRecentProtocolMenu();
        ver = obj.Protocol.meta.protocolVersion;
        obj.Figure.Name = sprintf('Protocol Designer  [%s]', ver);
        obj.setStatus(sprintf('Saved protocol to %s', obj.CurrentProtocolPath), ...
            'Ctrl+S now saves directly to the current file; Ctrl+Shift+S saves as a new file.');
        return
    end

    obj.onSaveAs();
end

