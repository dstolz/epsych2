function RememberRecentConfig(self, cfn)
% RememberRecentConfig(self, cfn)
% Persist a loaded config path and refresh its last-loaded timestamp.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
%   cfn (char|string) - Full path to a successfully loaded .config file.
% Outputs
%   None.

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