function setLastBrowseDirectory(~, folderPath)
    if isstring(folderPath)
        folderPath = char(folderPath);
    end
    if ~isempty(folderPath) && isfolder(folderPath)
        setappdata(0, 'EPsychProtocolDesignerLastBrowseDirectory', folderPath);
    end
end

