function selectedModuleRow = getSelectedModuleRow(obj)
    selectedModuleRow = 0;
    if isempty(obj.Figure) || ~isvalid(obj.Figure)
        return
    end

    userData = obj.Figure.UserData;
    if isstruct(userData) && isfield(userData, 'SelectedModuleRow') && ~isempty(userData.SelectedModuleRow)
        selectedModuleRow = double(userData.SelectedModuleRow);
    end
end