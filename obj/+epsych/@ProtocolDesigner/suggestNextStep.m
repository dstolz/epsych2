function nextStep = suggestNextStep(obj)
% suggestNextStep(obj)
% Return a short next-step hint based on the current designer state.
%
% Returns:
% 	nextStep	- Suggested follow-up action for the footer status label.
    if isempty(obj.Protocol.Interfaces)
        nextStep = 'Choose an interface type, then click Add Interface.';
        return
    end

    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        nextStep = 'Select an interface in the tree to review its modules.';
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    if isempty(iface.Module)
        if obj.canEditInterfaceModules(iface)
            nextStep = 'Add a module to the selected interface.';
        else
            nextStep = 'Review the interface options and required hardware files.';
        end
        return
    end

    module = obj.getSelectedTargetModule();
    if isempty(module)
        nextStep = 'Select a module in the target module list to edit its parameters.';
        return
    end

    if isempty(module.Parameters)
        nextStep = 'Add a parameter to the selected module.';
        return
    end

    if obj.Protocol.COMPILED.ntrials > 0
        nextStep = 'Review the compiled preview or save the protocol.';
    else
        nextStep = 'Review parameter values, then click Compile.';
    end
end