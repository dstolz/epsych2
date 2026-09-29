function T = parameters(protocol, options)
% T = epsych.ParameterDefaults.parameters(protocol)
% T = epsych.ParameterDefaults.parameters(protocol, IncludeHidden=false, IncludeIneligible=true)
% Every parameter of PROTOCOL a default can be given, one row each, in protocol
% order -- the rows gui.ParameterDefaultsEditor lists.
%
% Options:
%   IncludeHidden     - include parameters with Visible false (default true).
%                       Hidden parameters take defaults too: resetSession
%                       returns them to Values{1} at every run start.
%   IncludeIneligible - also list parameters that cannot take a default
%                       (triggers, buffers, expressions...), with the reason in
%                       Eligibility.Reason (default false).
%
% Returns:
%   T - (1,:) struct: Interface, Module, Name, Key, Label, Param (hw.Parameter),
%       Eligibility (see epsych.ParameterDefaults.eligibility).
%
% See also: epsych.ParameterDefaults.eligibility, epsych.ParameterDefaults.resolve
arguments
    protocol (1,1) epsych.Protocol
    options.IncludeHidden (1,1) logical = true
    options.IncludeIneligible (1,1) logical = false
end

T = struct('Interface', {}, 'Module', {}, 'Name', {}, 'Key', {}, 'Label', {}, ...
    'Param', {}, 'Eligibility', {});

for iface = protocol.Interfaces
    itype = char(iface.Type);
    for m = iface.Module
        for P = m.Parameters
            if ~P.Visible && ~options.IncludeHidden, continue, end
            e = epsych.ParameterDefaults.eligibility(P);
            if ~(e.CanSetValue || e.CanSetBounds) && ~options.IncludeIneligible
                continue
            end
            d = epsych.ParameterDefaults.blank();
            d.Interface = itype;
            d.Module = m.Name;
            d.Name = P.Name;
            T(end+1) = struct('Interface', itype, 'Module', m.Name, 'Name', P.Name, ...
                'Key', epsych.ParameterDefaults.key(d), ...
                'Label', epsych.ParameterDefaults.label(d), ...
                'Param', P, 'Eligibility', e);
        end
    end
end
end
