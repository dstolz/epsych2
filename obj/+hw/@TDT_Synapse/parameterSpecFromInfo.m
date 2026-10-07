function [spec, notes] = parameterSpecFromInfo(name, info)
% spec = hw.TDT_Synapse.parameterSpecFromInfo(name, info)
% [spec, notes] = hw.TDT_Synapse.parameterSpecFromInfo(name, info)
% Translate one SynapseAPI getParameterInfo record into hw.Parameter
% metadata. Pure: no client, no object, so the whole mapping is testable
% with a struct.
%
% What Synapse reports and what hw.Parameter accepts differ in every field
% that is validated:
%   Type   - Synapse says 'Float', 'Int' or 'Logic' (SynapseAPI manual,
%            getParameterInfo); hw.Parameter wants 'Float', 'Integer',
%            'Boolean'. An array of any of them is a 'Buffer', the type the
%            runtime reads and writes as a whole.
%   Array  - 'No', or 'Yes' when Synapse is at design time and does not yet
%            know the size (every legacy-circuit array, and User gizmo tag
%            arrays), or the element count once an experiment is running.
%            The client turns the count into a number.
%   Access - the manual does not list the values, so matching is on the
%            words: a record that allows both reading and writing maps to
%            'Any', one that names only one of them to that one, and
%            anything else to 'Any' with a note -- the toolbox default, and
%            the only reading under which a write is still attempted.
%   Min/Max - NaN or missing (a read-only parameter declares no bounds)
%            means the hw.Parameter defaults, -Inf and Inf; a gui edit
%            field refuses NaN limits outright. A magnitude of 1e20 or more
%            means the same: that is what Synapse reports for every tag of
%            a legacy circuit, which declares no bounds either, and
%            [-1e20 1e20] as a control's limits is noise.
%
% A record with no fields (Synapse listed the tag but would not describe
% it) yields conservative metadata -- 'Undefined', access 'Any', no bounds,
% the same as hw.TDT_RPcox gives a tag of a type it does not know -- and
% Described = false.
%
% EPsych's tag conventions are applied exactly as hw.TDT_RPcox applies
% them to the same circuit: a leading '!' is a trigger, and a leading '_',
% '~' or '#' hides the parameter from GUIs. Nothing else about a name is
% interpreted. In particular the runtime's required tags (x_NewTrial_<box>,
% x_ResetTrig_<box>, x_TrialComplete_<box>) come out as ordinary
% parameters, and the two that are pulsed are marked as triggers in
% ProtocolDesigner, as they are for an RPcox protocol over the same .rcx.
%
% Confirmed against a live Synapse (2026-10-07, RZ6 in legacy mode, Idle):
% every tag of the circuit came back Type 'Float', Access 'Read / Write',
% Min/Max -1e20/1e20, Array 'No' -- the FIR coefficient buffer included --
% so a design-time read cannot tell a buffer from a scalar. Modern gizmos
% reported 'Logic' and 'Int', 'Read', and real bounds.
%
% Parameters:
%   name - Parameter tag name, as Synapse lists it.
%   info - Struct from SynapseAPI.getParameterInfo: fields Name, Unit, Min,
%          Max, Access, Type, Array. Any may be missing; [] or a struct
%          with no fields is "undescribed".
%
% Returns:
%   spec  - Struct with fields Name, Unit, Min, Max, Access, Type, isArray,
%           Size (element count when Synapse gave one, else NaN),
%           isTrigger, Visible, Described.
%   notes - String array, one line per field that fell back to a default
%           for a reason worth logging (unknown type or access, bounds
%           Synapse gave that could not be read). Empty when every field
%           mapped cleanly.
%
% See also: hw.TDT_Synapse.populateModuleParametersFromGizmo, hw.Parameter

arguments
    name (1,:) char
    info = struct()
end

notes = strings(1, 0);

described = isstruct(info) && isscalar(info) && ~isempty(fieldnames(info));
if ~described
    info = struct();
end

isTrigger = local_isTrigger(name);
visible = local_isVisible(name);

% ---- Array / size --------------------------------------------------------
arrayField = local_field(info, 'Array', 'No');
sz = nan;
isArray = false;
if ischar(arrayField) || isstring(arrayField)
    isArray = strcmpi(strtrim(char(arrayField)), 'Yes');
elseif isnumeric(arrayField) && isscalar(arrayField) && isfinite(arrayField)
    isArray = arrayField > 1;
    if arrayField >= 1
        sz = double(arrayField);
    end
end

% ---- Type ----------------------------------------------------------------
rawType = local_field(info, 'Type', '');
if isArray
    type = 'Buffer';
elseif ~described
    type = 'Undefined';
else
    [type, known] = local_mapType(rawType);
    if ~known
        notes(end+1) = sprintf("type '%s' is not one Synapse documents; parameter created as Undefined", ...
            local_str(rawType));
    end
end

% ---- Access --------------------------------------------------------------
rawAccess = local_field(info, 'Access', '');
[access, known] = local_mapAccess(rawAccess);
if described && ~known
    notes(end+1) = sprintf("access '%s' not recognized; parameter created as readable and writable", ...
        local_str(rawAccess));
end

% ---- Bounds --------------------------------------------------------------
[minValue, ok] = local_bound(local_field(info, 'Min', nan), -inf);
if ~ok
    notes(end+1) = sprintf("minimum '%s' could not be read; no lower bound applied", ...
        local_str(local_field(info, 'Min', '')));
end
[maxValue, ok] = local_bound(local_field(info, 'Max', nan), inf);
if ~ok
    notes(end+1) = sprintf("maximum '%s' could not be read; no upper bound applied", ...
        local_str(local_field(info, 'Max', '')));
end
if minValue > maxValue
    notes(end+1) = sprintf("bounds [%g %g] are reversed; no bounds applied", minValue, maxValue);
    minValue = -inf;
    maxValue = inf;
end

% ---- Unit ----------------------------------------------------------------
unit = local_field(info, 'Unit', '');
if ischar(unit) || isstring(unit)
    unit = char(strtrim(string(unit)));
else
    unit = '';
end

spec = struct( ...
    'Name',      name, ...
    'Unit',      unit, ...
    'Min',       minValue, ...
    'Max',       maxValue, ...
    'Access',    access, ...
    'Type',      type, ...
    'isArray',   isArray, ...
    'Size',      sz, ...
    'isTrigger', isTrigger, ...
    'Visible',   visible, ...
    'Described', described);

end


function tf = local_isTrigger(name)
% The repository's prefix, as hw.TDT_RPcox reads it.
tf = ~isempty(name) && name(1) == '!';
end


function tf = local_isVisible(name)
% The hidden-parameter prefixes, as hw.TDT_RPcox reads them ('%' never
% gets this far: filterParameterNames drops it, as RPcox does).
tf = isempty(name) || ~any(name(1) == '_~#');
end


function v = local_field(s, field, default)
v = default;
if isfield(s, field) && ~isempty(s.(field))
    v = s.(field);
end
end


function [type, known] = local_mapType(raw)
known = true;
switch lower(strtrim(local_str(raw)))
    case {'float', 'single', 'double'}
        type = 'Float';
    case {'int', 'integer'}
        type = 'Integer';
    case {'logic', 'logical', 'bool', 'boolean'}
        type = 'Boolean';
    otherwise
        type = 'Undefined';
        known = false;
end
end


function [access, known] = local_mapAccess(raw)
% Matched on words rather than exact strings because the manual does not
% list them; what matters is whether a write will be attempted.
known = true;
s = lower(strtrim(local_str(raw)));
s = regexprep(s, '\s+', '');
canRead  = contains(s, 'read') || any(strcmp(s, {'r', 'ro'}));
canWrite = contains(s, 'write') || any(strcmp(s, {'w', 'wo'}));
if any(strcmp(s, {'both', 'any', 'rw', 'r/w', 'readwrite', 'read/write'})) || (canRead && canWrite)
    access = 'Any';
elseif canRead
    access = 'Read';
elseif canWrite
    access = 'Write';
else
    access = 'Any';
    known = false;
end
end


function [b, ok] = local_bound(raw, default)
% A bound is a finite or infinite number. NaN is Synapse's "none" (str2double
% of an empty field in the client) and is not a failure; so is a magnitude
% of 1e20 or more, the sentinel a legacy circuit's tags all carry.
UNBOUNDED = 1e20;

ok = true;
b = default;
if isnumeric(raw) && isscalar(raw)
    if ~isnan(raw) && abs(raw) < UNBOUNDED
        b = double(raw);
    end
elseif ischar(raw) || isstring(raw)
    parsed = str2double(raw);
    if ~isnan(parsed)
        if abs(parsed) < UNBOUNDED
            b = parsed;
        end
    elseif strlength(strtrim(string(raw))) > 0
        ok = false;
    end
else
    ok = false;
end
end


function s = local_str(v)
if ischar(v)
    s = v;
elseif isstring(v) && isscalar(v)
    s = char(v);
elseif isnumeric(v) || islogical(v)
    s = mat2str(v);
else
    s = class(v);
end
end
