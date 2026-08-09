function setLastProtocolFilePath(~, filePath)
    if isstring(filePath)
        filePath = char(filePath);
    end

    filePath = strtrim(filePath);
    if isempty(filePath)
        return
    end

    setappdata(0, 'EPsychProtocolDesignerLastProtocolFilePath', filePath);
end