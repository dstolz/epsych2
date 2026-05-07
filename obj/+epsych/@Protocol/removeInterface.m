function removeInterface(obj, identifier)
% removeInterface(obj, identifier)
%
% Remove an interface by index or type. Cannot remove the only interface.
%
% Parameters:
%   identifier (char | numeric) - Interface type/name or 1-based index to remove

if length(obj.Interfaces) == 1
    vprintf(0, 1, 'Cannot remove the only interface (Software)');
    return
end

idx = [];

if isnumeric(identifier) && isscalar(identifier)
    if identifier >= 1 && identifier <= length(obj.Interfaces)
        idx = double(identifier);
    end
elseif isstring(identifier) || ischar(identifier)
    name = char(identifier);
    for i = 1:length(obj.Interfaces)
        iface_type = char(obj.Interfaces(i).Type);
        if strcmp(iface_type, name)
            idx = i;
            break
        end
    end
end

if isempty(idx)
    vprintf(0, 1, 'Interface not found');
    return
end

removed_is_software = isa(obj.Interfaces(idx), 'hw.Software');
obj.Interfaces(idx) = [];

if removed_is_software
    replacement = [];
    for i = 1:length(obj.Interfaces)
        if isa(obj.Interfaces(i), 'hw.Software')
            replacement = obj.Interfaces(i);
            break
        end
    end

    if isempty(replacement)
        replacement = hw.Software();
        obj.Interfaces = [replacement, obj.Interfaces];
    end

    obj.SoftwareModule = replacement;
end
