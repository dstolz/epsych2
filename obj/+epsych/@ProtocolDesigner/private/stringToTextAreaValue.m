function values = stringToTextAreaValue(~, textValue)
    if isstring(textValue)
        textValue = char(textValue);
    end

    if isempty(textValue)
        values = {''};
        return
    end

    values = regexp(textValue, '\r\n|\n|\r', 'split');
    if isempty(values)
        values = {textValue};
    end
end

