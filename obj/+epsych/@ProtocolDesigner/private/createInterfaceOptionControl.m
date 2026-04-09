function control = createInterfaceOptionControl(obj, parent, field, position)
    defaultValue = obj.formatInterfaceDefault(field.defaultValue, field.isList);
    if field.getFile || field.getFolder
        control = obj.createPathPickerControl(parent, field, position, defaultValue);
        return
    end

    switch field.controlType
        case 'dropdown'
            items = field.choices;
            if isempty(items)
                items = {defaultValue};
            end
            control = uidropdown(parent, ...
                'Items', items, ...
                'Position', position);
            if any(strcmp(defaultValue, items))
                control.Value = defaultValue;
            else
                control.Value = items{1};
            end
        case 'multiselect'
            items = field.choices;
            if isempty(items)
                items = obj.parseList(defaultValue);
            end
            control = uilistbox(parent, ...
                'Items', items, ...
                'Position', [position(1) position(2) position(3) 56], ...
                'Multiselect', 'on');
            if iscell(field.defaultValue)
                selectedItems = field.defaultValue;
            else
                selectedItems = obj.parseList(defaultValue);
            end
            selectedItems = intersect(selectedItems, items, 'stable');
            if isempty(selectedItems)
                control.Value = {};
            else
                control.Value = selectedItems;
            end
        case 'numeric'
            numericDefault = str2double(defaultValue);
            if isnan(numericDefault)
                numericDefault = 0;
            end
            control = uieditfield(parent, 'numeric', ...
                'Position', position, ...
                'Value', numericDefault);
        case 'checkbox'
            control = uicheckbox(parent, ...
                'Position', [position(1) position(2) 180 position(4)], ...
                'Text', '', ...
                'Value', logical(field.defaultValue));
        case 'textarea'
            control = uitextarea(parent, ...
                'Position', [position(1) position(2) position(3) 52], ...
                'Value', {defaultValue});
        otherwise
            control = uieditfield(parent, 'text', ...
                'Position', position, ...
                'Value', defaultValue);
    end
end

