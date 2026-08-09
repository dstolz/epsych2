function setSelectedModuleRow(obj, selectedModuleRow)
    if isempty(obj.Figure) || ~isvalid(obj.Figure)
        return
    end

    userData = obj.Figure.UserData;
    if ~isstruct(userData)
        userData = struct();
    end
    userData.SelectedModuleRow = double(selectedModuleRow);
    obj.Figure.UserData = userData;
end