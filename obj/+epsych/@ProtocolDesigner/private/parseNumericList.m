function values = parseNumericList(obj, rawValue)
    if isnumeric(rawValue)
        values = double(rawValue);
        return
    end

    if iscell(rawValue)
        parts = cellstr(string(rawValue));
    else
        parts = obj.parseList(rawValue);
    end

    if isempty(parts)
        values = [];
        return
    end

    values = str2double(parts);
end