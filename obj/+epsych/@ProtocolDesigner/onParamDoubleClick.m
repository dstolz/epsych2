function onParamDoubleClick(obj, evt)
% onParamDoubleClick(obj, evt)
% Open a detail dialog for the double-clicked parameter row.
% Shows all metadata, current value, expression info, pair membership,
% and lists parameters that reference this one via expressions.
%
% Parameters:
%   evt - CellDoubleClickedData from the TableParams uitable.
    idx = evt.Index;
    if isempty(idx)
        return
    end

    row = idx(1, 1);
    if row < 1 || row > numel(obj.ParameterHandles)
        return
    end

    parameter = obj.ParameterHandles{row};
    obj.showParameterDetailsDialog(parameter);
end
