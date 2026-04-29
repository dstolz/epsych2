function onNew(obj)
% onNew(obj)
% Create a new empty protocol, prompting the user to discard unsaved changes
% when necessary.
    if ~obj.confirmDiscardChanges()
        return
    end

    obj.Protocol = epsych.Protocol();
    obj.CurrentProtocolPath = '';
    obj.IsModified_ = false;
    obj.refreshUI();
    obj.setStatus('New protocol created', ...
        'Add interfaces and parameters to build your protocol.');
end
