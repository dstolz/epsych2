function rawValue = readInterfaceControlValue(~, control, field)
    if isstruct(control)
        control = control.Primary;
    end

    if strcmp(field.controlType, 'dropdown')
        rawValue = control.Value;
    elseif strcmp(field.controlType, 'multiselect')
        rawValue = cellstr(control.Value);
    elseif strcmp(field.controlType, 'checkbox')
        rawValue = control.Value;
    elseif field.getFile && isa(control, 'matlab.ui.control.TextArea')
        rawValue = cellstr(control.Value);
    elseif isa(control, 'matlab.ui.control.NumericEditField')
        rawValue = control.Value;
    elseif isa(control, 'matlab.ui.control.TextArea')
        rawValue = strjoin(control.Value, ', ');
    else
        rawValue = control.Value;
    end
end

