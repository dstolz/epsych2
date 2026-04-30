function openProtocolFile(obj, filePath)
% openProtocolFile(obj, filePath)
% Load a protocol file and refresh the designer state around it.
%
% Parameters:
%	filePath	- Protocol file to load.
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