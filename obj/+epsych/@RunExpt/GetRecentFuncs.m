function recent = GetRecentFuncs(self, prefKey)
% recent = GetRecentFuncs(self, prefKey)
% Return the persisted most-recently-used function-name list for a Customize
% dialog field, pruning entries that no longer resolve on the path.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
%   prefKey (char|string) - Preference key under ep_RunExpt_FUNCS, one of
%       'RecentSavingFcn' or 'RecentAddSubjectFcn'.
% Outputs
%   recent (1,:) cell - Row cell array of resolvable function names,
%       most-recent-first.
% Notes
%   Mirrors GetRecentConfigs: normalizes stored values, prunes unresolvable
%   entries, and re-persists the cleaned list when it changes.

if ~isscalar(self)
    recent = {};
    return
end

prefKey = char(string(prefKey));
recent = getpref('ep_RunExpt_FUNCS', prefKey, {});

if isstring(recent)
    recent = cellstr(recent(:));
elseif ischar(recent)
    recent = {recent};
elseif ~iscell(recent)
    recent = {};
end

recent = recent(:)';
recent = cellfun(@(v) char(string(v)), recent, 'UniformOutput', false);
recent = recent(~cellfun(@isempty, recent));

if isempty(recent)
    recent = {};
else
    keep = cellfun(@resolves_, recent);
    recent = recent(keep);
end

stored = getpref('ep_RunExpt_FUNCS', prefKey, {});
if ~isequal(stored, recent)
    setpref('ep_RunExpt_FUNCS', prefKey, recent)
end

% -----------------------------------------------------------------------
function tf = resolves_(name)
% True when name resolves on the path. Static methods are not found by
% which(), so handle the built-in default add-subject method explicitly.
if strcmp(name, 'epsych.DefaultSubject.open')
    tf = ~isempty(which('epsych.DefaultSubject'));
else
    tf = ~isempty(which(name));
end
