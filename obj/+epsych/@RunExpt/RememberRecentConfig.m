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

if numel(recent) > 9
    recent = recent(1:9);
end

setpref('ep_RunExpt_Setup','RecentConfigs',recent)
self.UpdateRecentConfigsMenu