function [field, auto] = resolveParameter(sess, settings)
% [field, auto] = resolveParameter(sess, settings)
% The DATA field a staircase analysis of this session tracks:
% settings.Parameter when it names one, else the session's best candidate
% (behavior.Session.candidates), resolved per session.
%
% Returns:
%   field - the field, or "" when settings name none and the session has no
%           candidate. A field the session does not have is returned as
%           named; staircase() and analyze() report that.
%   auto  - true when the field was chosen from the candidates
%
% See also: behavior.Session.candidates, behavior.Settings

arguments
    sess (1,1) behavior.Session
    settings (1,1) behavior.Settings
end

auto = settings.Parameter == "";
if ~auto
    field = settings.Parameter;
elseif height(sess.Candidates) > 0
    field = string(sess.Candidates.Field(1));
else
    field = "";
end

end
