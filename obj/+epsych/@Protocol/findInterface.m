function hwif = findInterface(obj, name)
% hwif = findInterface(obj, name)
%
% Find and return an interface by name or type.
%
% Parameters:
%   name (char) - Name or Type of interface to find
%
% Returns:
%   hwif - hw.Interface handle, or empty if not found
arguments
    obj
    name (1,:) char
end

hwif = [];

% Try exact name match first
for i = 1:length(obj.Interfaces)
    if isprop(obj.Interfaces(i), 'Name') && ~isempty(obj.Interfaces(i).Name)
        if strcmp(obj.Interfaces(i).Name, name)
            hwif = obj.Interfaces(i);
            return
        end
    end
end

% Fall back to type match (compare Type property)
for i = 1:length(obj.Interfaces)
    iface_type = char(obj.Interfaces(i).Type);
    if strcmp(iface_type, name)
        hwif = obj.Interfaces(i);
        return
    end
end
