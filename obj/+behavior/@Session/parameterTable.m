function P = parameterTable(protocol)
% P = behavior.Session.parameterTable(protocol)
% Every parameter in a snapshot's protocol, one row each, as DATA saves it.
%
% Field is the DATA field a parameter is saved under
% (matlab.lang.makeValidName of its Name, as hw.Parameter.validName); an
% infinite bound saved as the text "Inf"/"-Inf" (hw.Parameter.toStruct)
% reads back as Inf. A snapshot from before 2026-08, or a legacy Info, has no
% InterfaceData and gives an empty table.
%
% This reads what behavior.Catalog's scan reads into a row's ParameterMeta,
% for a session loaded from a bare path, which has no row.
%
% Parameters:
%   protocol - Snapshot.Protocol (struct with InterfaceData)
%
% Returns:
%   P - table Field, Name, Unit (string), Min, Max (double), Type,
%       Interface, Module (string)
%
% See also: behavior.Session.parameterMeta, epsych.SessionSnapshot

P = table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', {'Field','Name','Unit','Min','Max','Type','Interface','Module'});

try
    ifaces = reshape(protocol.InterfaceData, 1, []);
catch
    return
end

blocks = cellfun(@localInterface, ifaces, 'UniformOutput', false);
rows = vertcat(cell(0, 8), blocks{:});
if isempty(rows), return, end
P = cell2table(rows, 'VariableNames', P.Properties.VariableNames);

end




function rows = localInterface(iface)
rows = cell(0, 8);
try
    mods = reshape(iface.Modules, 1, []);
catch
    return
end
ifaceName = localField(iface, 'Type');
blocks = cellfun(@(m) localModule(m, ifaceName), mods, 'UniformOutput', false);
rows = vertcat(rows, blocks{:});
end




function rows = localModule(mod, ifaceName)
rows = cell(0, 8);
try
    pars = reshape(mod.Parameters, 1, []);
catch
    return
end
modName = localField(mod, 'Name');
if modName == "", modName = localField(mod, 'Label'); end
blocks = cellfun(@(par) localParameter(par, ifaceName, modName), pars, 'UniformOutput', false);
rows = vertcat(rows, blocks{:});
end




function row = localParameter(par, ifaceName, modName)
row = cell(0, 8);
name = localField(par, 'Name');
if name == "", return, end
row = {string(matlab.lang.makeValidName(char(name))), name, ...
    localField(par, 'Unit'), localBound(par, 'Min'), localBound(par, 'Max'), ...
    localField(par, 'Type'), ifaceName, modName};
end




function v = localField(s, name)
% Text from a saved struct's field, "" when it has none: these structs come
% from files written by every release, so a missing field is expected.
v = "";
try
    x = s.(name);
    if (ischar(x) || isstring(x)) && ~isempty(x)
        v = string(x(1,:));
    end
catch
end
end




function b = localBound(par, name)
b = NaN;
try
    x = par.(name);
    if ischar(x) || isstring(x)
        b = str2double(x);
    elseif isnumeric(x) && isscalar(x)
        b = double(x);
    end
catch
end
end
