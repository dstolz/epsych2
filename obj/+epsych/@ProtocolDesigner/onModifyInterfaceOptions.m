function onModifyInterfaceOptions(obj)
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.setStatus('No interface selected for modification', 'Select an interface row in Current Interfaces first.');
        uialert(obj.Figure, 'Select an interface row in Current Interfaces first.', 'No Interface Selected');
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    try
        [spec, options] = obj.getInterfaceEditState(iface);
        updatedOptions = obj.promptForInterfaceOptions(spec, options, 'Apply Options', 'interface');
        if isempty(updatedOptions)
            obj.setStatus(sprintf('Modify %s cancelled', char(iface.Type)), ...
                'Review the interface options and reopen the dialog when ready.');
            return
        end

        replacement = spec.createFcn(updatedOptions);
        if ~isempty(iface.Module)
            replacement = obj.cloneModulesToInterface(iface, replacement);
        end
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
        obj.setStatus(sprintf('Updated options for %s', char(replacement.Type)), ...
            'Review affected modules and parameters, then compile again.');
    catch ME
        obj.setStatus(sprintf('Modify interface failed: %s', ME.message), ...
            'Check the option values and required files, then try again.');
        uialert(obj.Figure, ME.message, 'Modify Interface Failed');
    end
end