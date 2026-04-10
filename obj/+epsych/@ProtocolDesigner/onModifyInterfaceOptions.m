function onModifyInterfaceOptions(obj)
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.LabelStatus.Text = 'Select an interface to modify';
        uialert(obj.Figure, 'Select an interface row in Current Interfaces first.', 'No Interface Selected');
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    try
        [spec, options] = obj.getInterfaceEditState(iface);
        updatedOptions = obj.promptForInterfaceOptions(spec, options, 'Apply Options');
        if isempty(updatedOptions)
            obj.LabelStatus.Text = sprintf('Modify %s cancelled', char(iface.Type));
            return
        end

        replacement = spec.createFcn(updatedOptions);
        obj.Protocol.replaceInterface(interfaceIndex, replacement);
        obj.refreshParameterTab();

        selectedLabel = obj.interfaceLabel(replacement, interfaceIndex);
        if any(strcmp(selectedLabel, obj.DropDownTargetInterface.Items))
            obj.DropDownTargetInterface.Value = selectedLabel;
            obj.onTargetInterfaceChanged();
        end
        if any(strcmp(selectedLabel, obj.DropDownInterfaceFilter.Items))
            obj.DropDownInterfaceFilter.Value = selectedLabel;
            obj.refreshParameterTable();
        end
        obj.SelectedInterfaceRow = interfaceIndex;
        obj.LabelStatus.Text = sprintf('Updated options for %s', char(replacement.Type));
    catch ME
        obj.LabelStatus.Text = sprintf('Modify interface failed: %s', ME.message);
        uialert(obj.Figure, ME.message, 'Modify Interface Failed');
    end
end