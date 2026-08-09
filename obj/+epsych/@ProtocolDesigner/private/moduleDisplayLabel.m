function label = moduleDisplayLabel(~, module, moduleIdx)
    if nargin < 3 || isempty(moduleIdx)
        moduleIdx = double(module.Index);
    end

    if strcmp(module.Name, module.Label)
        label = sprintf('%d: %s', moduleIdx, module.Name);
    else
        label = sprintf('%d: %s [%s]', moduleIdx, module.Name, module.Label);
    end
end