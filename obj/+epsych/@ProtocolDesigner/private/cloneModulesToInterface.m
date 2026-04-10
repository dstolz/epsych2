function targetIface = cloneModulesToInterface(~, sourceIface, targetIface)
    modules = hw.Module.empty(1, 0);
    for moduleIdx = 1:length(sourceIface.Module)
        sourceModule = sourceIface.Module(moduleIdx);
        clonedModule = hw.Module(targetIface, sourceModule.Label, sourceModule.Name, sourceModule.Index);
        clonedModule.Fs = sourceModule.Fs;
        if isstruct(sourceModule.Info)
            clonedModule.Info = sourceModule.Info;
        end

        for paramIdx = 1:length(sourceModule.Parameters)
            sourceParam = sourceModule.Parameters(paramIdx);
            clonedParam = hw.Parameter(targetIface);
            clonedParam.Module = clonedModule;
            clonedParam.fromStruct(sourceParam.toStruct());
            clonedModule.Parameters(end + 1) = clonedParam;
        end

        modules(end + 1) = clonedModule;
    end

    if isa(targetIface, 'hw.Software')
        targetIface.set_module(modules);
    elseif ismethod(targetIface, 'setModules')
        targetIface.setModules(modules);
    elseif ismethod(targetIface, 'set_module')
        targetIface.set_module(modules);
    else
        error('Interface type %s does not support editing its module list in ProtocolDesigner.', char(targetIface.Type));
    end
end