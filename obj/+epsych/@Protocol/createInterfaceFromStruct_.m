function interface = createInterfaceFromStruct_(~, ifaceStruct)
% interface = createInterfaceFromStruct_(obj, ifaceStruct)
%
% Reconstruct an hw.Interface from the serialized struct produced by
% toStruct(). Restores interface type, modules, and parameters.
%
% Parameters:
%   ifaceStruct - Struct with fields: Type, ClassName, Server,
%                 ConnectionType, Modules (cell array of module structs)
%
% Returns:
%   interface - Reconstructed hw.Interface instance

ifaceType = char(string(ifaceStruct.Type));
switch ifaceType
    case 'Software'
        interface = hw.Software();
    case 'TDT_Synapse'
        server = 'localhost';
        if isfield(ifaceStruct, 'Server') && ~isempty(ifaceStruct.Server)
            server = char(string(ifaceStruct.Server));
        end
        interface = hw.TDT_Synapse(server, Connect = false);
    case 'TDT_RPcox'
        connectionType = 'GB';
        if isfield(ifaceStruct, 'ConnectionType') && ~isempty(ifaceStruct.ConnectionType)
            connectionType = char(string(ifaceStruct.ConnectionType));
        elseif isfield(ifaceStruct, 'Modules') && ~isempty(ifaceStruct.Modules) ...
                && isfield(ifaceStruct.Modules{1}.Info, 'ConnectionType') ...
                && ~isempty(ifaceStruct.Modules{1}.Info.ConnectionType)
            connectionType = char(string(ifaceStruct.Modules{1}.Info.ConnectionType));
        end
        interface = hw.TDT_RPcox({}, {}, {}, Interface = connectionType, Connect = false);
    case 'Intan_RHX'
        host = '127.0.0.1';
        if isfield(ifaceStruct, 'Host') && ~isempty(ifaceStruct.Host)
            host = char(string(ifaceStruct.Host));
        end
        port = 5000;
        if isfield(ifaceStruct, 'Port') && ~isempty(ifaceStruct.Port)
            port = double(ifaceStruct.Port);
        end
        interface = hw.Intan_RHX(host, port, Connect = false);

    otherwise
        interface = hw.Software();
end

modules = hw.Module.empty(1, 0);
if isfield(ifaceStruct, 'Modules') && ~isempty(ifaceStruct.Modules)
    for moduleIdx = 1:length(ifaceStruct.Modules)
        moduleStruct = ifaceStruct.Modules{moduleIdx};
        module = hw.Module(interface, char(moduleStruct.Label), char(moduleStruct.Name), ...
            uint8(moduleStruct.Index));
        if isfield(moduleStruct, 'Fs') && ~isempty(moduleStruct.Fs)
            module.Fs = double(moduleStruct.Fs);
        end
        if isfield(moduleStruct, 'Info') && isstruct(moduleStruct.Info)
            module.Info = moduleStruct.Info;
        end
        if isfield(moduleStruct, 'Parameters') && ~isempty(moduleStruct.Parameters)
            for paramIdx = 1:length(moduleStruct.Parameters)
                paramStruct = moduleStruct.Parameters{paramIdx};
                parameter = hw.Parameter(interface);
                parameter.Module = module;
                parameter.fromStruct(paramStruct);
                module.Parameters(end + 1) = parameter; %#ok<AGROW>
            end
        end
        modules(end + 1) = module; %#ok<AGROW>
    end
end

if isa(interface, 'hw.Software')
    interface.set_module(modules);
else
    interface.setModules(modules);
end
end
