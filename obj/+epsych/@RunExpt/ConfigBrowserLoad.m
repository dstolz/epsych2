function ConfigBrowserLoad(self, fig, lb)
% ConfigBrowserLoad — Callback for "Load" button in BrowseConfigs().
arguments
    self
    fig (1,1)
    lb (1,1)
end

if ~isgraphics(fig) || ~isgraphics(lb), return, end

data = fig.UserData;
sel = string(lb.Value);
idx = find(data.Items == sel,1,'first');
if isempty(idx), return, end

cfn = string(data.FullPaths(idx));

if isfield(data,'RestoreOnTop')
    self.ConfigBrowserRestoreOnTop(data.RestoreOnTop)
end

try
    delete(fig)
catch
end

self.LoadConfig(cfn)
