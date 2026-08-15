function DefineLogPath(self)
% obj.DefineLogPath
% Prompt for and persist the directory the +eplog daily error logs are written
% to, then re-point the running logger at it.
%
% The default is <epsych root>/.error_logs, which .gitignore excludes. Rigs
% whose repository lives on a read-only or cloud-synced share point this at
% local storage instead.
%
% See also: eplog.setLogDir, eplog.defaultLogDir, epsych.RunExpt.OpenCustomizeDialog

startDir = eplog.defaultLogDir();
if ~isfolder(startDir), startDir = char(self.DefaultDataPath); end

ontop = self.AlwaysOnTop(false);
pth = uigetdir(startDir,'Select Error Log Directory');
self.AlwaysOnTop(ontop);

if isequal(pth,0), return, end

try
    d = eplog.setLogDir(pth);
catch ME
    vprintf(0,1,ME);
    uialert(self.H.figure1, ME.message, 'Error Log Path', 'Icon', 'error');
    return
end

self.setStatus(sprintf('Error log directory: %s',d));
end
