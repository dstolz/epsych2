function parameterType = getCompiledWriteParamType(obj, writeParamName)
    parameterType = '';
    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        ifaceType = char(iface.Type);
        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            for paramIdx = 1:length(module.Parameters)
                parameter = module.Parameters(paramIdx);
                if ~parameter.Visible || strcmp(parameter.Access, 'Read')
                    continue
                end

                if strcmp(ifaceType, 'Software')
                    compiledName = parameter.Name;
                else
                    compiledName = sprintf('%s.%s', module.Name, parameter.Name);
                end

                if strcmp(compiledName, writeParamName)
                    parameterType = parameter.Type;
                    return
                end
            end
        end
    end
end

