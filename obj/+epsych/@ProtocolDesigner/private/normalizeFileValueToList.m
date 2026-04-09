function fileList = normalizeFileValueToList(~, fileValue)
    if isempty(fileValue)
        fileList = {};
        return
    end

    if isnumeric(fileValue) || islogical(fileValue)
        fileList = {};
        return
    end

    if isstring(fileValue)
        fileValue = cellstr(fileValue);
    end

    if ischar(fileValue)
        if isempty(strtrim(fileValue))
            fileList = {};
        else
            fileList = {fileValue};
        end
        return
    end

    if iscell(fileValue)
        if numel(fileValue) == 1 && iscell(fileValue{1})
            fileValue = fileValue{1};
        end
        fileList = cellfun(@(item) char(string(item)), fileValue, 'UniformOutput', false);
        fileList = fileList(~cellfun(@isempty, fileList));
        return
    end

    fileList = {char(string(fileValue))};
end

