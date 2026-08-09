function ClearRecentConfigs(self)
% ClearRecentConfigs(self)
% Empty the persistent recent-config registry and refresh the submenu.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
% Outputs
%   None.

setpref('ep_RunExpt_Setup','RecentConfigs',{})
setpref('ep_RunExpt_Setup','RecentConfigLoadedOn',struct('path',{},'loadedOn',{}))
self.UpdateRecentConfigsMenu
