function addInterface(obj, interface, options)
% addInterface(obj, interface, varargin)
% 
% Add an hw.Interface instance to this protocol.
%
% Parameters:
%   interface - An hw.Interface subclass (hw.TDT_RPcox, hw.TDT_Synapse, etc.)
%   Name (char, default=interface.Type) - Optional alias for this interface
arguments
    obj
    interface (1,1) hw.Interface
    options.Name (1,:) char = char(interface.Type)
end

% Check for duplicate interface types
existing_types = arrayfun(@(iface) char(iface.Type), obj.Interfaces, 'UniformOutput', false);
if any(strcmp(char(interface.Type), existing_types))
    vprintf(0, 1, 'Interface of type "%s" already exists', char(interface.Type));
    return
end

% Append interface
obj.Interfaces = [obj.Interfaces, interface];

if isa(interface, 'hw.Software')
    obj.SoftwareModule = interface;
end
