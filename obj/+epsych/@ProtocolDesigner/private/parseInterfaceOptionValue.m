function value = parseInterfaceOptionValue(obj, field, rawValue)
    if isstring(rawValue)
        rawValue = char(rawValue);
    end

    switch field.inputType
        case 'numeric'
            if isnumeric(rawValue)
                value = rawValue;
            else
                value = str2double(rawValue);
            end
        case {'logical', 'boolean', 'bool'}
            if islogical(rawValue)
                value = rawValue;
            elseif isnumeric(rawValue)
                value = logical(rawValue);
            else
                value = strcmpi(strtrim(rawValue), 'true') || strcmp(rawValue, '1');
            end
        case 'choice'
            value = strtrim(rawValue);
        otherwise
            if field.isList
                if iscell(rawValue)
                    value = rawValue;
                else
                    value = obj.parseList(rawValue);
                end
            else
                value = strtrim(rawValue);
            end
    end
end

