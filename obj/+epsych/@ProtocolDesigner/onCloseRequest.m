function onCloseRequest(obj)
% onCloseRequest(obj)
% Handle figure close request, prompting the user to discard unsaved changes
% when necessary before closing.
    if ~obj.confirmDiscardChanges()
        return
    end

    % Tool dialogs are sibling figures, not children of obj.Figure, so closing
    % the designer does not take them with it.
    siblingFigures = {obj.FindReplaceFigure, obj.InterfaceFigure, ...
        obj.OptionsFigure, obj.PreviewFigure, obj.CheckCalcFigure};
    for idx = 1:numel(siblingFigures)
        fig = siblingFigures{idx};
        if ~isempty(fig) && isvalid(fig)
            delete(fig);
        end
    end

    delete(obj.Figure);
end
