function tf = sessionFlagValue(field, value)
% tf = epsych.SubjectRoster.sessionFlagValue(field, value)
% What a yes/no session setting MEANS: the stored value, or the built-in
% default when nothing is stated.
%
% A SESSION_FLAG_FIELDS value is stored tri-state (1, 0, NaN = not stated).
% This is the one place NaN is resolved, so the session, the commit-time
% mismatch check and the manager's Settings column cannot come to read "not
% stated" differently: it is SESSION_FLAG_DEFAULTS.(field), always, and so a
% membership that states the default and one that states nothing agree.
%
% Parameters:
%   field - 'RecordBuffers' or 'RecordStimulusSettings'.
%   value - the stored setting, in any form sessionFlag accepts. A value it
%           does not recognize reads as not stated.
%
% Returns:
%   tf - logical scalar.
%
% See also: epsych.SubjectRoster.sessionFlag, epsych.SubjectRoster.assignToSession
arguments
    % Literals, because a validator cannot name a class constant; the
    % standing proof checks this list against SESSION_FLAG_FIELDS.
    field (1,:) char {mustBeMember(field, {'RecordBuffers','RecordStimulusSettings'})}
    value
end

v = epsych.SubjectRoster.sessionFlag(value);
if isnan(v)
    tf = epsych.SubjectRoster.SESSION_FLAG_DEFAULTS.(field);
else
    tf = v == 1;
end
end
