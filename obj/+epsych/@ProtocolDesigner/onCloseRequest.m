function onCloseRequest(obj)
% onCloseRequest(obj)
% Handle figure close request, prompting the user to discard unsaved changes
% when necessary before closing.
    if ~obj.confirmDiscardChanges()
        return
    end

    delete(obj.Figure);
end
