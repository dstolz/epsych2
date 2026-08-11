function refreshInterfaceBuilder(obj)
% refreshInterfaceBuilder(obj)
% Reload the addable interface types into the Add Interface controls.
% No-op while the Interfaces dialog is closed.
    if isempty(obj.DropDownInterfaceType) || ~isvalid(obj.DropDownInterfaceType)
        return
    end

    specs = obj.getAddableInterfaceSpecs();
    if isempty(specs)
        obj.DropDownInterfaceType.Items = {'<none>'};
        obj.DropDownInterfaceType.Value = '<none>';
        obj.LabelInterfaceDescription.Text = 'All available interface types are already present in the protocol.';
        obj.BtnAddInterface.Enable = false;
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
    obj.BtnAddInterface.Enable = true;
end