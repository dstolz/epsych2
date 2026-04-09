function onRemoveParam(obj)
    if obj.SelectedParamRow < 1 || obj.SelectedParamRow > numel(obj.ParameterHandles)
        obj.LabelStatus.Text = 'Select a parameter to remove';
        return
    end

    parameter = obj.ParameterHandles{obj.SelectedParamRow};
    module = parameter.Module;
    keepMask = module.Parameters ~= parameter;
    module.Parameters = module.Parameters(keepMask);

    obj.refreshParameterTab();
    obj.LabelStatus.Text = sprintf('Removed parameter %s', parameter.Name);
end

