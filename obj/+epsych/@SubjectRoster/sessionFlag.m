function [v, ok] = sessionFlag(value)
% [v, ok] = epsych.SubjectRoster.sessionFlag(value)
% Canonical stored form of a yes/no session setting (SESSION_FLAG_FIELDS).
%
% The fields are tri-state for the reason RecordVideo is: a roster written
% before they existed has to keep meaning what it meant then, so "not stated"
% needs a value of its own rather than being read as "no". Stored as a double
% so NaN can carry it.
%
% Accepts what a checkbox, a script, or a hand-edited file is likely to hold:
%   true / 1 / "on" / "yes" / "true"                 -> 1
%   false / 0 / "off" / "no" / "false"               -> 0
%   NaN / [] / "" / "inherit" / "default"            -> NaN
%
% Never throws: assignToSession reads these from records it did not write, and
% a malformed value must not refuse a batch. Anything unrecognized comes back
% as NaN with ok = false, and a caller that is WRITING the value (addProject,
% updateProject, updateMembership) turns that into an error.
%
% Parameters:
%   value - the setting in any of the forms above.
%
% Returns:
%   v  - 1, 0, or NaN.
%   ok - false when value was not recognized (v is then NaN).
%
% See also: epsych.SubjectRoster.sessionFlagValue, epsych.SubjectRoster.recordVideoSetting
arguments
    value
end

v = NaN;
ok = true;

if isempty(value)
    return
end

if ischar(value) || (isstring(value) && isscalar(value))
    switch lower(strtrim(char(value)))
        case {'on','yes','true','1'}
            v = 1;
        case {'off','no','false','0'}
            v = 0;
        case {'inherit','default','nan',''}
            v = NaN;
        otherwise
            ok = false;
    end
    return
end

if (isnumeric(value) || islogical(value)) && isscalar(value)
    value = double(value);
    if isnan(value)
        return
    end
    if value == 1 || value == 0
        v = value;
        return
    end
end

ok = false;
end
