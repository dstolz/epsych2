function text = getFileNameDisplayText(~, rawValue)
    rawText = char(string(rawValue));
    if isempty(strtrim(rawText))
        text = '';
        return
    end

    [~, fileName, extension] = fileparts(rawText);
    if isempty(fileName) && isempty(extension)
        text = rawText;
    else
        text = sprintf('%s%s', fileName, extension);
    end
end

