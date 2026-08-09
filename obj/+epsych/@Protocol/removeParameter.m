function removeParameter(obj, interfaceName, name)
% removeParameter(obj, interfaceName, name)
%
% Remove a parameter from a specific interface.
%
% Parameters:
%   interfaceName (char) - Name of target interface
%   name (char) - Parameter name to remove
arguments
    obj
    interfaceName (1,:) char
    name (1,:) char
end

hwif = obj.findInterface(interfaceName);
if isempty(hwif)
    vprintf(0, 1, 'Interface "%s" not found', interfaceName);
    return
end

% Find and remove parameter from all modules
for m = 1:length(hwif.Module)
    idx = [];
    for p = 1:length(hwif.Module(m).Parameters)
        if strcmp(hwif.Module(m).Parameters(p).Name, name)
            idx = p;
            break
        end
    end
    if ~isempty(idx)
        hwif.Module(m).Parameters(idx) = [];
        return
    end
end

vprintf(0, 1, 'Parameter "%s" not found in interface "%s"', name, interfaceName);
