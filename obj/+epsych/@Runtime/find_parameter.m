function P = find_parameter(obj, name, options)
% P = find_parameter(obj, name, options)
% Return hw.Parameter handles matching the given name(s), with optional
% pre-filtering by interface class, interface type string, or module name.
%
% Parameters:
%   obj                               - epsych.Runtime instance.
%   name                              - Parameter name(s); char, string, or cellstr.
%   options.Interface                 - Interface class name(s) to restrict to (char, string, or
%                                       cellstr); e.g. 'hw.Software'. Uses isa() matching.
%   options.InterfaceName             - hw.Interface.Type string(s) to restrict to (char, string,
%                                       or cellstr); e.g. 'Software', 'TDT_Synapse'.
%   options.ModuleName                - hw.Module.Name string(s) to restrict to (char, string,
%                                       or cellstr); e.g. 'Params'.
%   options.includeInvisible          - Include invisible parameters (default: false).
%   options.silenceParameterNotFound  - Suppress not-found warnings (default: false).
%
% Returns:
%   P - hw.Parameter array in requested name order; empty if no match.
arguments
    obj
    name
    options.Interface = {}
    options.InterfaceName = {}
    options.ModuleName = {}
    options.includeInvisible (1,1) logical = false
    options.includeTriggers (1,1) logical = true
    options.silenceParameterNotFound (1,1) logical = false
end
P = obj.all_parameters( ...
    includeInvisible = options.includeInvisible, ...
    includeTriggers = options.includeTriggers, ...
    Interface        = options.Interface);

if ~isempty(options.InterfaceName)
    ifNames = cellstr(options.InterfaceName);
    P = P(arrayfun(@(p) any(strcmp(p.HW.Type, ifNames)), P));
end

if ~isempty(options.ModuleName)
    modNames = cellstr(options.ModuleName);
    P = P(arrayfun(@(p) any(strcmp(p.Module.Name, modNames)), P));
end

name = cellstr(name);
ind = ismember({P.Name},name);
if any(ind)
    P = P(ind);
    [ind,idx] = ismember(name,{P.Name});
    P = P(idx(ind));
else
    P = [];
    if ~options.silenceParameterNotFound
        cellfun(@(a) vprintf(0,1,'Parameter "%s" was not found on any modules',a),name)
    end
end
end
