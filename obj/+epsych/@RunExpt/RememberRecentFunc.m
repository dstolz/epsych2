function RememberRecentFunc(self, prefKey, name)
% RememberRecentFunc(self, prefKey, name)
% Record an accepted function name at the front of the most-recently-used
% list for a Customize dialog field.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
%   prefKey (char|string) - Preference key under ep_RunExpt_FUNCS,
%       e.g. 'RecentAddSubjectFcn'.
% Outputs
%   None.
% Notes
%   Prepend, case-insensitive dedupe, cap. Empty names are ignored.

MAX_RECENT = 12;

name = char(string(name));
if isempty(strtrim(name)), return, end

prefKey = char(string(prefKey));
recent = self.GetRecentFuncs(prefKey);

if isempty(recent)
    recent = {name};
else
    keep = ~strcmpi(recent, name);
    recent = [{name} recent(keep)];
end

if numel(recent) > MAX_RECENT
    recent = recent(1:MAX_RECENT);
end

setpref('ep_RunExpt_FUNCS', prefKey, recent)
