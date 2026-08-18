function targetIface = cloneModulesToInterface(obj, sourceIface, targetIface)
    modules = hw.Module.empty(1, 0);
    parameters = hw.Parameter.empty(1, 0);
    paramStructs = {};
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
            % Restore metadata only; Value is restored below once every
            % parameter exists and is wired to its module, so parameters
            % with expressions can resolve sibling references regardless
            % of their declaration order.
            paramStruct = sourceParam.toStruct();
            clonedParam.fromStruct(paramStruct, false);
            clonedModule.Parameters(end + 1) = clonedParam;
            parameters(end + 1) = clonedParam;
            paramStructs{end + 1} = paramStruct;
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

    % Restoring Value evaluates each parameter's Expression, which may name a
    % parameter on another interface (e.g. "... - Params.RespWinPreStim"). The
    % resolver finds those through iface.Runtime, and the designer has no
    % epsych.Runtime, so stand the Protocol in for the restore pass. targetIface
    % is linked explicitly: the caller swaps it into the protocol only after
    % this returns.
    restoreLink = obj.Protocol.linkInterfacesForValueRestore(targetIface);
    for paramIdx = 1:numel(parameters)
        parameters(paramIdx).fromStruct(paramStructs{paramIdx});
    end
    delete(restoreLink)
end