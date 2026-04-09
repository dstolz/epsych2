function value = parseValue(~, rawValue)
    if isstring(rawValue)
        rawValue = char(rawValue);
    end

    if ischar(rawValue)
        numericValue = str2num(rawValue); %#ok<ST2NM>
        if ~isempty(numericValue)
            value = numericValue;
        else
            value = rawValue;
        end
    else
        value = rawValue;
    end
end

