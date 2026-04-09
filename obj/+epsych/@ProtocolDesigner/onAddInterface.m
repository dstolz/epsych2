function onAddInterface(obj)
    specs = obj.getAvailableInterfaceSpecs();
    labels = cellfun(@(spec) spec.label, specs, UniformOutput = false);
    [selection, ok] = listdlg('PromptString', 'Select interface type to add:', ...
        'SelectionMode', 'single', ...
        'ListString', labels);
    if ~ok || isempty(selection)
        return
    end

    try
        spec = specs{selection};
        options = obj.promptForInterfaceOptions(spec);
        if isempty(options)
            return
        end

        interface = spec.createFcn(options);
        obj.Protocol.addInterface(interface);
        obj.refreshParameterTab();
        obj.LabelStatus.Text = sprintf('Added interface %s', char(interface.Type));
    catch ME
        obj.LabelStatus.Text = sprintf('Add interface failed: %s', ME.message);
    end
end

