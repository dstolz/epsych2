function updatedModule = applyUpdatedModuleOptions(obj, iface, moduleIndex, moduleOptions)
    if moduleIndex < 1 || moduleIndex > length(iface.Module)
        error('Selected module index %d is out of range.', moduleIndex);
    end

    sourceModule = iface.Module(moduleIndex);
    switch char(iface.Type)
        case 'TDT_RPcox'
            moduleLabel = obj.getUniqueModuleTextForEdit(iface, ...
                obj.getSingleModuleOptionText(moduleOptions, 'moduleType', sourceModule.Label), ...
                'Label', moduleIndex);
            moduleName = obj.getUniqueModuleTextForEdit(iface, ...
                obj.getSingleModuleOptionText(moduleOptions, 'moduleAlias', sourceModule.Name), ...
                'Name', moduleIndex);

            updatedModule = hw.Module(iface, moduleLabel, moduleName, sourceModule.Index);
            updatedModule.Fs = sourceModule.Fs;
            if isstruct(sourceModule.Info)
                updatedModule.Info = sourceModule.Info;
            else
                updatedModule.Info = struct();
            end

            updatedModule.Info.RPvdsFile = obj.getSingleModuleOptionText(moduleOptions, 'RPvdsFile', '');
            updatedModule.Info.Number = obj.getSingleModuleOptionNumeric(moduleOptions, 'number', double(sourceModule.Index));
            updatedModule.Info.FsOverride = obj.getSingleModuleOptionNumeric(moduleOptions, 'fs', 0);
            if isprop(iface, 'ConnectionType') && ~isempty(iface.ConnectionType)
                updatedModule.Info.ConnectionType = iface.ConnectionType;
            elseif isfield(updatedModule.Info, 'ConnectionType') && ~isempty(updatedModule.Info.ConnectionType)
                updatedModule.Info.ConnectionType = char(string(updatedModule.Info.ConnectionType));
            else
                updatedModule.Info.ConnectionType = 'GB';
            end
        otherwise
            error('Modify Module options are not implemented for interface type %s.', char(iface.Type));
    end

    for paramIdx = 1:length(sourceModule.Parameters)
        sourceParam = sourceModule.Parameters(paramIdx);
        clonedParam = hw.Parameter(iface);
        clonedParam.Module = updatedModule;
        clonedParam.fromStruct(sourceParam.toStruct());
        updatedModule.Parameters(end + 1) = clonedParam;
    end

    modules = iface.Module;
    modules(moduleIndex) = updatedModule;
    obj.replaceInterfaceModules(iface, modules);
end