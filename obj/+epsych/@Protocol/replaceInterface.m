function replaceInterface(obj, identifier, interface)
% replaceInterface(obj, identifier, interface)
%
% Replace one existing interface by index or type.
%
% Parameters:
%   identifier - numeric index or interface type string
%   interface - replacement hw.Interface instance
arguments
    obj
    identifier
    interface (1,1) hw.Interface
end

idx = [];

if isnumeric(identifier) && isscalar(identifier)
    if identifier >= 1 && identifier <= length(obj.Interfaces)
        idx = double(identifier);
    end
elseif isstring(identifier) || ischar(identifier)
    name = char(identifier);
    for i = 1:length(obj.Interfaces)
        ifaceType = char(obj.Interfaces(i).Type);
        if strcmp(ifaceType, name)
            idx = i;
            break
        end
    end
end

if isempty(idx)
    error('Interface not found');
end

obj.Interfaces(idx) = interface;

if isa(interface, 'hw.Software')
    obj.SoftwareModule = interface;
elseif idx == 1 && isa(obj.SoftwareModule, 'hw.Software') && isa(obj.Interfaces(1), 'hw.Software')
    obj.SoftwareModule = obj.Interfaces(1);
end
