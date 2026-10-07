function [keep, dropped] = filterParameterNames(names)
% keep = hw.TDT_Synapse.filterParameterNames(names)
% [keep, dropped] = hw.TDT_Synapse.filterParameterNames(names)
% Remove from a getParameterNames listing the tags EPsych never exposes and
% the ones the Synapse client cannot address.
%
% A legacy processor lists every parameter tag in its circuit, which is
% more than a circuit's author meant as parameters:
%   - '%'-prefixed tags are RPvds-internal, dropped on hw.TDT_RPcox too;
%   - names holding '/', '\' or '|', or 'rPvDsHElpEr', belong to RPvds helper
%     objects and error strings that leak through the legacy HAL (the
%     filter ReadRPvdsTags has applied since 2014);
%   - a name with '#', '%', '?' or whitespace cannot travel in the URL path
%     the client builds for it ('/params/RZ6(1).#Tag' ends at the '#'), so
%     a read or write would address the wrong thing. '#'-prefixed tags are
%     a hidden-parameter convention on hw.TDT_RPcox; over Synapse they are
%     out of reach, and the circuit has to spell them with '~' instead.
%
% Parameters:
%   names - cellstr or string array of tag names.
%
% Returns:
%   keep    - 1xN cellstr of the names to expose, in their original order.
%   dropped - 1xM struct array with fields Name and Reason for every name
%             removed, for the caller to log.
%
% See also: hw.TDT_Synapse.populateModuleParametersFromGizmo, ReadRPvdsTags

arguments
    names {mustBeText}
end

names = reshape(cellstr(names), 1, []);

keep = {};
dropped = struct('Name', {}, 'Reason', {});

for k = 1:numel(names)
    name = names{k};
    reason = local_reason(name);
    if isempty(reason)
        keep{end+1} = name;
    else
        dropped(end+1) = struct('Name', name, 'Reason', reason);
    end
end

end


function reason = local_reason(name)
reason = '';
if isempty(name)
    reason = 'empty name';
elseif name(1) == '%'
    reason = 'RPvds-internal tag';
elseif any(ismember(name, '/\|')) || contains(name, 'rPvDsHElpEr')
    reason = 'RPvds helper object, not a parameter';
elseif any(ismember(name, '#%?')) || any(isspace(name))
    reason = 'name cannot be addressed over the Synapse HTTP API';
end
end
