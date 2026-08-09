function value = getFieldOr(S, name, default)
% value = teensy.getFieldOr(S, name, default)
% Read one field from a serialized struct, falling back to a default.
%
% Structs written by an earlier version of the teensy model classes can be
% missing fields that were added later. Every fromStruct method in the package
% reads through this helper so an old .etsm file, or an undo snapshot taken
% before a field existed, loads with the current defaults instead of erroring.
%
% A stored empty numeric ([]) is also treated as "absent" whenever the default
% is not itself numeric: MAT and JSON round-trips both collapse unset text,
% logical and object fields to [], which cannot satisfy a typed property.
% Numeric defaults keep a stored [] so a genuinely empty pin list survives.
%
% Parameters
%   S       - Scalar struct to read. Anything else yields the default.
%   name    - Field name to read.
%   default - Value returned when the field is missing or unusable.
%
% Returns
%   value   - S.(name) when usable, otherwise default.
%
% Example
%   name = string(teensy.getFieldOr(S, 'Name', ""));
%   pins = teensy.getFieldOr(S, 'PwmPins', []);
%
% See also: teensy.Program, teensy.issue

arguments
    S
    name (1,:) char
    default
end

value = default;

if ~isstruct(S) || ~isscalar(S)
    return
end

% isfield is the entire point of this helper: tolerating fields an older save
% never wrote. It is the one sanctioned exception to the no-isfield rule.
if isfield(S, name)
    value = S.(name);
end

if isnumeric(value) && isempty(value) && ~isnumeric(default)
    value = default;
end
