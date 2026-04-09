function displayItems = getFileDisplayItems(obj, fileList)
    if isempty(fileList)
        displayItems = {};
        return
    end

    displayItems = cell(size(fileList));
    for idx = 1:numel(fileList)
        filePath = char(string(fileList{idx}));
        [folderPath, fileName, extension] = fileparts(filePath);
        shortFolder = obj.getShortDisplayPath(folderPath);
        displayItems{idx} = sprintf('%s%s  |  %s', fileName, extension, shortFolder);
    end

    displayItems = obj.makeUniqueDisplayItems(displayItems);
end

