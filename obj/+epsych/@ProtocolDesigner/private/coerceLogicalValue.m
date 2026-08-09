function logicalValue = coerceLogicalValue(obj, rawValue)
    if islogical(rawValue)
        logicalValue = rawValue;
        return
    end

    if isnumeric(rawValue)
        if isempty(rawValue)
            logicalValue = false;
        else
            logicalValue = rawValue ~= 0;
        end
        return
    end

    if isstring(rawValue)
        if isscalar(rawValue)
            rawValue = char(rawValue);
        else
            rawValue = cellstr(rawValue);
        end
    end

    if ischar(rawValue)
        textValue = lower(strtrim(rawValue));
        if any(strcmp(textValue, {'true', 't', 'yes', 'y', 'on'}))
            logicalValue = true;
        elseif any(strcmp(textValue, {'false', 'f', 'no', 'n', 'off'}))
            logicalValue = false;
        else
            numericValue = str2double(textValue);
            if isnan(numericValue)
                logicalValue = false;
            else
                logicalValue = numericValue ~= 0;
            end
        end
        return
    end

    if iscell(rawValue)
        logicalValue = false(1, numel(rawValue));
        for idx = 1:numel(rawValue)
            logicalValue(idx) = obj.coerceLogicalValue(rawValue{idx});
        end
        return
    end

    logicalValue = false;
end

