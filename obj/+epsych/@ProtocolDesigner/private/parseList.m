function values = parseList(~, rawValue)
    if isstring(rawValue)
        rawValue = char(rawValue);
    end

    parts = regexp(rawValue, '\s*[,;]\s*', 'split');
    parts = parts(~cellfun(@isempty, parts));
    if isempty(parts)
        values = {rawValue};
    else
        values = parts;
    end
end

