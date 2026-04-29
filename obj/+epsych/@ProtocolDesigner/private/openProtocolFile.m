function openProtocolFile(obj, filePath)
    if isstring(filePath)
        filePath = char(filePath);
    end

    warning('off', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
    obj.Protocol = epsych.Protocol.load(filePath);
    warning('on', 'MATLAB:dispatcher:UnresolvedFunctionHandle');

    obj.CurrentProtocolPath = filePath;
    obj.setLastProtocolFilePath(filePath);
    obj.setLastBrowseDirectory(fileparts(filePath));
    obj.addRecentProtocolPath(filePath);
    obj.refreshRecentProtocolMenu();
    obj.IsModified_ = false;
    obj.refreshUI();
end