function recent = GetRecentConfigs(self)
% GetRecentConfigs — Return the persisted recent configuration file list.
% Behavior
%   Normalizes preference storage to a row cell array of existing files and
%   trims the list to the most recent nine entries.

if ~isscalar(self)
    recent = {};
    return
end

recent = getpref('ep_RunExpt_Setup','RecentConfigs',{});

if isstring(recent)
    recent = cellstr(recent(:));
elseif ischar(recent)
    recent = {recent};
elseif ~iscell(recent)
    recent = {};
end

recent = recent(:)';
recent = recent(~cellfun(@isempty, recent));

if isempty(recent)
    return
end

keep = cellfun(@(p) exist(p,'file') == 2, recent);
recent = recent(keep);

if numel(recent) > 9
    recent = recent(1:9);
end

stored = getpref('ep_RunExpt_Setup','RecentConfigs',{});
if ~isequal(stored, recent)
    setpref('ep_RunExpt_Setup','RecentConfigs',recent)
end