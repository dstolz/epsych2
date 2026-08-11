function onOpenRecentProtocol(obj, filePath)
% onOpenRecentProtocol(obj, filePath)
% Open a protocol from the recent-files list after validating the path.
%
% Parameters:
%	filePath	- Saved protocol file path selected from the recent-files menu.
    if isstring(filePath)
        filePath = char(filePath);
    end

    if ~isfile(filePath)
        obj.removeRecentProtocolPath(filePath);
        obj.refreshRecentProtocolMenu();
        obj.setStatus(sprintf('Recent protocol not found: %s', filePath), ...
            'The missing file was removed from Recent Protocols.');
        return
    end

    if ~obj.confirmDiscardChanges()
        return
    end

    convertedNames = obj.openProtocolFile(filePath);
    [~, fileName, extension] = fileparts(filePath);
    if isempty(convertedNames)
        obj.setStatus(sprintf('Loaded protocol %s%s', fileName, extension), ...
            'Review the loaded protocol or save it under a new name after editing.');
    else
        obj.setStatus(sprintf('Loaded protocol %s%s; converted %d constant expression(s) to fixed values (%s)', ...
            fileName, extension, numel(convertedNames), strjoin(convertedNames, ', ')), ...
            'Save the protocol to keep the converted values.');
    end
end