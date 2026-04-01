function RememberRecentConfig(self, cfn)
% RememberRecentConfig — Persist the most recently loaded configuration.

cfn = char(string(cfn));
recent = self.GetRecentConfigs;

if isempty(recent)
    recent = {cfn};
else
    keep = ~strcmpi(recent, cfn);
    recent = [{cfn} recent(keep)];
end

meta = getpref('ep_RunExpt_Setup','RecentConfigLoadedOn',struct('path',{},'loadedOn',{}));
if ~isstruct(meta) || ~all(isfield(meta,{'path','loadedOn'}))
    meta = struct('path',{},'loadedOn',{});
end

if ~isempty(meta)
    keepMeta = ~strcmpi({meta.path}, cfn);
    meta = meta(keepMeta);
end

meta = [struct('path',cfn,'loadedOn',now) meta];

setpref('ep_RunExpt_Setup','RecentConfigs',recent)
setpref('ep_RunExpt_Setup','RecentConfigLoadedOn',meta)
self.UpdateRecentConfigsMenu