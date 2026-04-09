function control = createPathPickerControl(obj, parent, field, position, defaultValue)
    browseWidth = 80;
    gap = 8;
    editorWidth = position(3) - browseWidth - gap;
    if editorWidth < 160
        editorWidth = position(3);
        browseWidth = 0;
        gap = 0;
    end

    if strcmp(field.controlType, 'textarea') || field.isList
        primary = uitextarea(parent, ...
            'Position', [position(1) position(2) editorWidth 52], ...
            'Value', obj.stringToTextAreaValue(defaultValue));
        buttonY = position(2) + 11;
    else
        primary = uieditfield(parent, 'text', ...
            'Position', [position(1) position(2) editorWidth position(4)], ...
            'Value', defaultValue);
        buttonY = position(2);
    end

    control = struct('Primary', primary);
    if browseWidth > 0
        control.Browse = uibutton(parent, 'push', ...
            'Text', 'Browse', ...
            'Position', [position(1) + editorWidth + gap buttonY browseWidth 28], ...
            'ButtonPushedFcn', @(~, ~) obj.onBrowseInterfacePath(control.Primary, field));
    else
        control.Browse = [];
    end
end

