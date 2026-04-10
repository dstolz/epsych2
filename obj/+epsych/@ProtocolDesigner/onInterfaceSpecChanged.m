function onInterfaceSpecChanged(obj)
    obj.refreshInterfaceBuilder();
    [spec, ~] = obj.getSelectedInterfaceSpec();
    obj.LabelStatus.Text = sprintf('Preparing a %s interface', spec.label);
end