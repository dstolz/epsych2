function onCloseRequest(obj)
% onCloseRequest(obj)
% Handle figure close request, prompting the user to discard unsaved changes
% when necessary before closing.
    if ~obj.confirmDiscardChanges()
        return
    end

    % The Find and Replace dialog is a sibling figure, not a child of obj.Figure.
    if ~isempty(obj.FindReplaceFigure) && isvalid(obj.FindReplaceFigure)
        delete(obj.FindReplaceFigure);
    end

    delete(obj.Figure);
end
