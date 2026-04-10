function onAddInterface(obj)
    try
        [spec, ~] = obj.getSelectedInterfaceSpec();
        options = obj.promptForInterfaceOptions(spec);
        if isempty(options)
            obj.LabelStatus.Text = sprintf('Add %s cancelled', spec.label);
            return
        end
        interface = spec.createFcn(options);
        obj.Protocol.addInterface(interface);
        obj.refreshParameterTab();
        newLabel = obj.interfaceLabel(interface, length(obj.Protocol.Interfaces));
        if any(strcmp(newLabel, obj.DropDownTargetInterface.Items))
            obj.DropDownTargetInterface.Value = newLabel;
            obj.onTargetInterfaceChanged();
        end
        if any(strcmp(newLabel, obj.DropDownInterfaceFilter.Items))
            obj.DropDownInterfaceFilter.Value = newLabel;
            obj.refreshParameterTable();
        end
        obj.LabelStatus.Text = sprintf('Added interface %s', char(interface.Type));
    catch ME
        obj.LabelStatus.Text = sprintf('Add interface failed: %s', ME.message);
    end
end

