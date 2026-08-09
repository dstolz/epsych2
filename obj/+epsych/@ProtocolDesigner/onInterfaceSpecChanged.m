function onInterfaceSpecChanged(obj)
    obj.refreshInterfaceBuilder();
    [spec, ~] = obj.getSelectedInterfaceSpec();
    obj.setStatus(sprintf('Preparing a %s interface', spec.label), ...
        'Review the interface options, then click Add Interface.');
end