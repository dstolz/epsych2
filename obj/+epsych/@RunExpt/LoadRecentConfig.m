function LoadRecentConfig(self, cfn)
% LoadRecentConfig(self, cfn)
% Load a config selected from the recent-config menu.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
%   cfn (char|string) - Full path to a config file.
% Outputs
%   None.
% Notes
%   If cfn no longer exists, removes stale entries from both recent path and
%   timestamp preferences before updating the menu.

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