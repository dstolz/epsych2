function DefineConfigBrowserRoot(self)
% DefineConfigBrowserRoot — Set the root folder for the Config Browser.
% Behavior
%   Stores the selected folder in preferences and uses it as the
%   parent directory for recursive "*.ecfg" browsing.
arguments
    self
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

p0 = getpref('ep_RunExpt_Setup','ConfigBrowserRootDir',"" );
if strlength(string(p0)) == 0
    p0 = getpref('ep_RunExpt_Setup','CDir',cd);
end
if ~exist(p0,'dir'), p0 = cd; end

ontop = self.AlwaysOnTop(false);
pth = uigetdir(p0,'Select Config Browser Root Folder');
self.AlwaysOnTop(ontop);

if isequal(pth,0) || strlength(string(pth))==0, return, end
setpref('ep_RunExpt_Setup','ConfigBrowserRootDir',pth)
vprintf(1,'Config browser root set to: %s',pth)
