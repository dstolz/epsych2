function description = describeInterfaceField(~, field)
    parts = {};
    if field.getFile
        if field.isList
            parts{end + 1} = 'Use Browse to select one or more files.'; %#ok<AGROW>
        else
            parts{end + 1} = 'Use Browse to select a file.'; %#ok<AGROW>
        end
    elseif field.getFolder
        parts{end + 1} = 'Use Browse to select a folder.'; %#ok<AGROW>
    end

    if strcmp(field.controlType, 'dropdown') && ~isempty(field.choices)
        parts{end + 1} = sprintf('Choices: %s.', strjoin(field.choices, ', ')); %#ok<AGROW>
    elseif strcmp(field.controlType, 'multiselect') && ~isempty(field.choices)
        parts{end + 1} = sprintf('Select one or more values from: %s.', strjoin(field.choices, ', ')); %#ok<AGROW>
    elseif strcmp(field.controlType, 'checkbox')
        parts{end + 1} = 'Toggle on or off.'; %#ok<AGROW>
    elseif field.isList
        parts{end + 1} = 'Enter multiple values separated by commas or semicolons.'; %#ok<AGROW>
    elseif strcmp(field.inputType, 'numeric')
        parts{end + 1} = 'Numeric value.'; %#ok<AGROW>
    end

    if isempty(parts)
        description = '';
    else
        description = strjoin(parts, ' ');
    end
end

