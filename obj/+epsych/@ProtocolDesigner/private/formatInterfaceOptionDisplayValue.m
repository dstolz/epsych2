function displayValue = formatInterfaceOptionDisplayValue(obj, field, rawValue)
    if nargin < 3
        rawValue = field.defaultValue;
    end

    if isempty(rawValue)
        if strcmp(field.controlType, 'checkbox') || ismember(field.inputType, {'logical', 'boolean', 'bool'})
            displayValue = '[ ] false';
        else
            displayValue = '';
        end
        return
    end

    if strcmp(field.controlType, 'checkbox') || ismember(field.inputType, {'logical', 'boolean', 'bool'})
        if islogical(rawValue)
            isEnabled = rawValue;
        elseif isnumeric(rawValue)
            isEnabled = logical(rawValue);
        else
            isEnabled = any(strcmpi(strtrim(char(string(rawValue))), {'true', '1', 'yes', 'on'}));
        end
        if isEnabled
            displayValue = '[x] true';
        else
            displayValue = '[ ] false';
        end
        return
    end

    if field.isList
        if isnumeric(rawValue)
            displayValue = strjoin(arrayfun(@num2str, rawValue(:).', 'UniformOutput', false), ', ');
            return
        end
        if iscell(rawValue)
            values = cellstr(string(rawValue));
        else
            values = obj.parseList(rawValue);
        end
        displayValue = strjoin(values, ', ');
        return
    end

    if strcmp(field.controlType, 'dropdown')
        displayValue = sprintf('v %s', char(string(rawValue)));
        return
    end

    if strcmp(field.controlType, 'multiselect')
        if ~iscell(rawValue)
            rawValue = obj.parseList(rawValue);
        end
        if isempty(rawValue)
            displayValue = '[0 selected]';
        else
            displayValue = sprintf('[%d selected] %s', numel(rawValue), strjoin(cellstr(string(rawValue)), ', '));
        end
        return
    end

    if strcmp(field.controlType, 'numeric') || strcmp(field.inputType, 'numeric')
        if isnumeric(rawValue)
            displayValue = num2str(rawValue);
        else
            displayValue = char(string(rawValue));
        end
        return
    end

    if field.getFile || field.getFolder
        if iscell(rawValue)
            paths = cellstr(string(rawValue));
        else
            paths = obj.parseList(rawValue);
        end
        if isempty(paths)
            displayValue = '';
        elseif numel(paths) == 1
            displayValue = paths{1};
        else
            displayValue = sprintf('[%d paths] %s', numel(paths), paths{1});
        end
        return
    end

    displayValue = char(string(rawValue));
end