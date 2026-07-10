function [interface, parameters, paramStructs] = createInterfaceFromStruct_(~, ifaceStruct)
% [interface, parameters, paramStructs] = createInterfaceFromStruct_(obj, ifaceStruct)
%
% Reconstruct an hw.Interface from the serialized struct produced by
% toStruct(). Restores interface type, modules, and parameter *metadata*.
%
% Parameter Values are deliberately NOT restored here. Value assignment
% evaluates each parameter's Expression, which may reference parameters on
% other interfaces (e.g. a TDT parameter referencing a Software parameter).
% Those references can only resolve once every interface exists, so the
% caller (epsych.Protocol.fromStruct) restores Values in a single pass after
% all interfaces have been reconstructed.
%
% Parameters:
%   ifaceStruct - Struct with fields: Type, ClassName, Server,
%                 ConnectionType, Modules (cell array of module structs)
%
% Returns:
%   interface    - Reconstructed hw.Interface instance
%   parameters   - hw.Parameter handles awaiting Value restoration
%   paramStructs - Serialized structs aligned 1:1 with `parameters`

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
parameters = hw.Parameter.empty(1, 0);
paramStructs = {};
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
                % Restore metadata only; Values are restored by the caller
                % once every interface exists, so parameters with expressions
                % can resolve sibling and cross-interface references
                % regardless of their declaration order.
                parameter.fromStruct(paramStruct, false);
                module.Parameters(end + 1) = parameter;
                parameters(end + 1) = parameter;
                paramStructs{end + 1} = paramStruct;
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
