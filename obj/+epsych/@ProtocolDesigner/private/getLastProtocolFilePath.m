function filePath = getLastProtocolFilePath(~)
    filePath = getappdata(0, 'EPsychProtocolDesignerLastProtocolFilePath');
    if isempty(filePath)
        filePath = '';
    end
end