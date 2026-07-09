function loadConfigFromLink(self, configPath)
% loadConfigFromLink(self, configPath)
% Load a configuration requested through an "epsych://" link, guarding
% against interrupting an active experiment. Brings the window to the front
% and notifies the user of the outcome; never auto-starts the experiment.
%
% Parameters:
%   configPath - Full path to the .ecfg file to load.
%
% See also: epsych.RunExpt.handleConfigLink, epsych.RunExpt.LoadConfig
arguments
    self
    configPath (1,1) string
end

% Bring the RunExpt window forward so the user sees the result.
if isfield(self.H,'figure1') && isgraphics(self.H.figure1)
    self.H.figure1.Visible = 'on';
    movegui(self.H.figure1,'onscreen');
    try
        figure(self.H.figure1);
    catch
    end
end

% Do not disturb a running experiment.
if self.STATE >= PRGMSTATE.RUNNING
    vprintf(0,1,'Config link ignored: an experiment is currently running (%s).', configPath);
    uialert(self.H.figure1, ...
        'An experiment is currently running. The config link was ignored to avoid interrupting it.', ...
        'EPsych','Icon','warning');
    return
end

if ~isfile(configPath)
    vprintf(0,1,'Config link points to a missing file: %s', configPath);
    uialert(self.H.figure1, ...
        sprintf('The configuration file could not be found:\n%s', configPath), ...
        'EPsych','Icon','error');
    return
end

self.LoadConfig(configPath);

uialert(self.H.figure1, ...
    sprintf('Loaded configuration:\n%s\n\nPress Run when ready.', configPath), ...
    'EPsych','Icon','success');
