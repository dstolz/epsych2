function [value, isArrayValue] = parseStringParameterValue(~, rawValue)
    if isstring(rawValue)
        rawValue = char(rawValue);
    end

    if ischar(rawValue)
        normalizedText = strrep(rawValue, sprintf('\r\n'), sprintf('\n'));
        normalizedText = strrep(normalizedText, sprintf('\r'), sprintf('\n'));
        parts = regexp(normalizedText, '\s*(?:;|\n)\s*', 'split');
        parts = parts(~cellfun(@isempty, parts));
        if isempty(parts)
            value = '';
            isArrayValue = false;
        elseif numel(parts) == 1
            value = parts{1};
            isArrayValue = false;
        else
            value = parts;
            isArrayValue = true;
        end
        return
    end

    if iscell(rawValue)
        values = cellfun(@(item) char(string(item)), rawValue(:).', 'UniformOutput', false);
        values = values(~cellfun(@isempty, values));
        if isempty(values)
            value = '';
            isArrayValue = false;
        elseif numel(values) == 1
            value = values{1};
            isArrayValue = false;
        else
            value = values;
            isArrayValue = true;
        end
        return
    end

    value = char(string(rawValue));
    isArrayValue = false;
end