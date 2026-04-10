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

            for idx = 1:moduleCount
                module = iface.Module(idx);
                options.RPvdsFile{idx} = module.Info.RPvdsFile;
                options.moduleType{idx} = module.Label;
                options.moduleAlias{idx} = module.Name;
            end

            if ~isempty(iface.HW)
                options.interface = iface.HW(1).INTERFACE;
                options.number = iface.HW(1).NUMBER;
                options.fs = iface.HW(1).FS;
            else
                options.interface = 'GB';
                options.number = 1;
                options.fs = 0;
            end

        otherwise
            error('Editing is not implemented for interface type %s.', ifaceType);
    end
end