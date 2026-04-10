function value = parseInterfaceOptionValue(obj, field, rawValue)
    if isstring(rawValue)
        rawValue = char(rawValue);
    end

    if field.isList
        switch field.inputType
            case 'numeric'
                value = obj.parseNumericList(rawValue);
            case {'logical', 'boolean', 'bool'}
                value = logical(obj.parseNumericList(rawValue));
            otherwise
                if iscell(rawValue)
                    value = rawValue;
                else
                    value = obj.parseList(rawValue);
                end
        end
        return
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
            value = strtrim(rawValue);
    end
end

