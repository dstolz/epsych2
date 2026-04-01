function LoadRecentConfig(self, cfn)
% LoadRecentConfig — Load a config file selected from the recent list.

cfn = string(cfn);

if exist(cfn,'file') ~= 2
    recent = self.GetRecentConfigs;
    if ~isempty(recent)
        recent = recent(~strcmpi(recent, char(cfn)));
        setpref('ep_RunExpt_Setup','RecentConfigs',recent)
    end

    meta = getpref('ep_RunExpt_Setup','RecentConfigLoadedOn',struct('path',{},'loadedOn',{}));
    if isstruct(meta) && all(isfield(meta,{'path','loadedOn'})) && ~isempty(meta)
        keep = ~strcmpi({meta.path}, char(cfn));
        meta = meta(keep);
        setpref('ep_RunExpt_Setup','RecentConfigLoadedOn',meta)
    end

    self.UpdateRecentConfigsMenu
    warndlg(sprintf('The file "%s" does not exist.',cfn),'RunExpt','modal')
    return
end

self.LoadConfig(cfn)