function parameter = getSelectedParameter(obj)
    if obj.SelectedParamRow < 1 || obj.SelectedParamRow > numel(obj.ParameterHandles)
        parameter = [];
        return
    end
    parameter = obj.ParameterHandles{obj.SelectedParamRow};
end

