function RefreshConfig(self)
% RefreshConfig — Reload the currently loaded configuration file from disk.
% Behavior
%   Re-runs LoadConfig on CurrentConfigFile, discarding any in-memory
%   changes (e.g. added/removed subjects) since it was last loaded/saved.
arguments
    self
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if strlength(self.CurrentConfigFile) == 0 || ~isfile(self.CurrentConfigFile)
    uialert(self.H.figure1,'No configuration file is currently loaded.','EPsych','Icon','info');
    return
end

vprintf(0,'Refreshing configuration file: ''%s''\n',self.CurrentConfigFile)
self.LoadConfig(self.CurrentConfigFile)
