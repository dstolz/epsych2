function [v, ok] = recordVideoSetting(value)
% [v, ok] = epsych.SubjectRoster.recordVideoSetting(value)
% Canonical form of a membership's RecordVideo setting.
%
% The field is tri-state because a roster written before it existed must keep
% meaning what it meant then: recording was the rig's toolbar toggle alone, so
% "no setting" has to be a value of its own rather than "off". Stored as a
% double so NaN can carry it, the same convention TimerPeriod uses.
%
% Accepts what a script, an edit, or a hand-edited file is likely to hold, so
% callers do not each re-implement the mapping:
%   true / 1 / "on"  / "record"           -> 1
%   false / 0 / "off" / "none"            -> 0
%   NaN / [] / "" / "rig" / "inherit"     -> NaN
%
% Never throws, because assignToSession reads it from records it did not write
% and a malformed value must not refuse a batch: anything unrecognized comes
% back as NaN with ok = false, and the caller decides whether that is an error.
%
% Parameters:
%   value - the setting in any of the forms above.
%
% Returns:
%   v  - 1, 0, or NaN.
%   ok - false when value was not recognized (v is then NaN).
%
% See also: epsych.SubjectRoster.setRecordVideo, epsych.SubjectRoster.assignToSession
arguments
    value
end

v = NaN;
ok = true;

if isempty(value)
    return
end

if ischar(value) || isstring(value)
    switch lower(strtrim(char(value)))
        case {'on','record','true','yes','1'}
            v = 1;
        case {'off','none','false','no','0'}
            v = 0;
        case {'rig','inherit','default','nan',''}
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
