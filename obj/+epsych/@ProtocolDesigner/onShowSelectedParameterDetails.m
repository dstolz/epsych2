function onShowSelectedParameterDetails(obj)
% onShowSelectedParameterDetails(obj)
% Open the details dialog for the currently selected parameter.
    row = obj.SelectedParamRow;
    if row < 1 || row > numel(obj.ParameterHandles)
        obj.setStatus('No parameter selected', ...
            'Select a parameter row and then press Ctrl+Shift+D to view details.');
        return
    end

    parameter = obj.ParameterHandles{row};
    obj.showParameterDetailsDialog(parameter);
end