function path = getCurrentControlPath(~, control, field)
    path = '';
    if isa(control, 'matlab.ui.control.TextArea')
        values = cellstr(control.Value);
        values = values(~cellfun(@isempty, values));
        if isempty(values)
            return
        end
        currentValue = values{1};
    else
        currentValue = control.Value;
    end

    if isstring(currentValue)
        currentValue = char(currentValue);
    end
    if isempty(currentValue)
        return
    end

    if field.getFolder
        candidatePath = currentValue;
    else
        candidatePath = fileparts(currentValue);
    end

    if isfolder(candidatePath)
        path = candidatePath;
    end
end

