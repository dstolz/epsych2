function onRemoveInterface(obj)
% onRemoveInterface(obj)
% Confirm and remove the selected interface from the protocol, then bring every
% control that names an interface back in step with what is left.
%
% A protocol always keeps one hw.Software interface (Protocol.removeInterface
% swaps in an empty one when the Software interface is removed), so "removing"
% Software resets it and the only interface cannot be removed at all; the status
% line says which of the three happened rather than assuming a removal.
    interfaceIndex = obj.getSelectedInterfaceRowIndex();
    if interfaceIndex < 1 || interfaceIndex > length(obj.Protocol.Interfaces)
        obj.setStatus('No interface selected for removal', 'Select an interface in the tree first.');
        return
    end

    iface = obj.Protocol.Interfaces(interfaceIndex);
    typeName = char(string(iface.Type));
    isSoftware = isa(iface, 'hw.Software');

    if isscalar(obj.Protocol.Interfaces)
        obj.setStatus(sprintf('Cannot remove %s: it is the only interface', typeName), ...
            'Add another interface first, or delete its parameters instead.');
        return
    end

    if isSoftware
        confirmLabel = 'Reset';
        question = sprintf(['A protocol always keeps a Software interface.\n' ...
            'Reset %s to an empty one? Its modules and parameters will be lost.'], typeName);
    else
        confirmLabel = 'Remove';
        question = sprintf('Remove interface %s?', typeName);
    end
    if ~strcmp(questdlg(question, 'Remove Interface', confirmLabel, 'Cancel', 'Cancel'), confirmLabel)
        return
    end

    % Interfaces are a heterogeneous handle array, which == cannot compare
    % whole, so match them one at a time.
    obj.Protocol.removeInterface(interfaceIndex);
    if any(arrayfun(@(candidate) candidate == iface, obj.Protocol.Interfaces))
        obj.setStatus(sprintf('Interface %s was not removed', typeName), ...
            'Check the command window for the reason.');
        return
    end

    % Settle the selection before refreshing, since the refresh reads it: the
    % interface that took the removed one's place (or the new last one), or the
    % fresh Software interface, and never a module of the interface that went.
    if isSoftware
        selectedRow = find(arrayfun(@(candidate) candidate == obj.Protocol.SoftwareModule, ...
            obj.Protocol.Interfaces), 1);
    else
        selectedRow = min(interfaceIndex, length(obj.Protocol.Interfaces));
    end
    obj.SelectedInterfaceRow = selectedRow;
    obj.setSelectedModuleRow(0);
    obj.IsModified_ = true;
    obj.refreshParameterTab();

    if isSoftware
        obj.setStatus(sprintf('Reset %s interface to an empty one', typeName), ...
            'Add parameters to it again, or review the remaining interfaces before compiling.');
    else
        obj.setStatus(sprintf('Removed interface %s', typeName), ...
            'Add another interface or review the remaining modules before compiling.');
    end
end
