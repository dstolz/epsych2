function refreshInterfaceBuilder(obj)
    specs = obj.getAvailableInterfaceSpecs();
    if isempty(specs)
        obj.DropDownInterfaceType.Items = {'<none>'};
        obj.DropDownInterfaceType.Value = '<none>';
        obj.LabelInterfaceDescription.Text = 'No interface types are available.';
        return
    end

    labels = cellfun(@(spec) spec.label, specs, 'UniformOutput', false);
    currentValue = '';
    if ~isempty(obj.DropDownInterfaceType.Items)
        currentValue = obj.DropDownInterfaceType.Value;
    end

    obj.DropDownInterfaceType.Items = labels;
    if any(strcmp(currentValue, labels))
        obj.DropDownInterfaceType.Value = currentValue;
    else
        obj.DropDownInterfaceType.Value = labels{1};
    end

    [spec, ~] = obj.getSelectedInterfaceSpec();
    obj.LabelInterfaceDescription.Text = spec.description;
end