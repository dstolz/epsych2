function valueText = formatStringParameterValue(~, rawValue)
    if isempty(rawValue)
        valueText = '';
        return
    end

    if ischar(rawValue)
        valueText = rawValue;
        return
    end

    if isstring(rawValue)
        values = cellstr(rawValue(:).');
        valueText = strjoin(values, '; ');
        return
    end

    if iscell(rawValue)
        values = cellfun(@(item) char(string(item)), rawValue(:).', 'UniformOutput', false);
        valueText = strjoin(values, '; ');
        return
    end

    valueText = char(string(rawValue));
end