function ConfigBrowserCancel(self, fig)
% ConfigBrowserCancel — Callback for closing/canceling the config browser.
arguments
    self
    fig (1,1)
end

if ~isgraphics(fig)
    return
end

data = fig.UserData;
if isfield(data,'RestoreOnTop')
    self.ConfigBrowserRestoreOnTop(data.RestoreOnTop)
end

try
    delete(fig)
catch
end
