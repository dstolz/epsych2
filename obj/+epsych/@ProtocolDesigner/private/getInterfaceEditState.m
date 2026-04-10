function [spec, options] = getInterfaceEditState(obj, iface)
    ifaceType = char(iface.Type);
    specs = obj.getAvailableInterfaceSpecs();
    specIndex = find(cellfun(@(entry) strcmp(char(string(entry.type)), ifaceType), specs), 1);
    if isempty(specIndex)
        error('No creation spec is available for interface type %s.', ifaceType);
    end

    spec = specs{specIndex};
    options = struct();

    switch ifaceType
        case 'Software'
            options = struct();

        case 'TDT_Synapse'
            options.server = iface.Server;

        case 'TDT_RPcox'
            moduleCount = length(iface.Module);
            options.RPvdsFile = cell(1, moduleCount);
            options.moduleType = cell(1, moduleCount);
            options.moduleAlias = cell(1, moduleCount);
            options.number = nan(1, moduleCount);
            options.fs = nan(1, moduleCount);

            for idx = 1:moduleCount
                module = iface.Module(idx);
                if isfield(module.Info, 'RPvdsFile')
                    options.RPvdsFile{idx} = module.Info.RPvdsFile;
                else
                    options.RPvdsFile{idx} = '';
                end
                options.moduleType{idx} = module.Label;
                options.moduleAlias{idx} = module.Name;
                if isfield(module.Info, 'Number') && ~isempty(module.Info.Number)
                    options.number(idx) = double(module.Info.Number);
                else
                    options.number(idx) = idx;
                end
                if isfield(module.Info, 'FsOverride') && ~isempty(module.Info.FsOverride)
                    options.fs(idx) = double(module.Info.FsOverride);
                else
                    options.fs(idx) = 0;
                end
            end

            if isprop(iface, 'ConnectionType') && ~isempty(iface.ConnectionType)
                options.connectionType = iface.ConnectionType;
            elseif moduleCount >= 1 && isfield(iface.Module(1).Info, 'ConnectionType') && ~isempty(iface.Module(1).Info.ConnectionType)
                options.connectionType = iface.Module(1).Info.ConnectionType;
            elseif ~isempty(iface.HW)
                options.connectionType = iface.HW(1).INTERFACE;
            else
                options.connectionType = 'GB';
            end

        otherwise
            error('Editing is not implemented for interface type %s.', ifaceType);
    end
end