function onRemoveParam(obj)
% onRemoveParam(obj)
% Remove the selected parameter from its parent module.
    if obj.SelectedParamRow < 1 || obj.SelectedParamRow > numel(obj.ParameterHandles)
        obj.setStatus('No parameter selected for removal', 'Select a parameter row in the table first.');
        return
    end

    parameter = obj.ParameterHandles{obj.SelectedParamRow};
    module = parameter.Module;
    keepMask = module.Parameters ~= parameter;
    module.Parameters = module.Parameters(keepMask);

    obj.IsModified_ = true;
    obj.refreshParameterTab();
    obj.setStatus(sprintf('Removed parameter %s', parameter.Name), ...
        'Add a replacement parameter or compile to confirm the remaining settings.');
end

