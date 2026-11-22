function onCloseRequest(self, ask)
% onCloseRequest(self)
% onCloseRequest(self, ask)
% Graceful shutdown of running experiment and UI.
% Behavior
%   Warns if running, stops the session as the Stop control would, releases
%   hardware, and deletes the main figure. Nothing is written to the machine
%   preferences: the session's FUNCS came from the subjects' memberships, and
%   persisting them here would turn one study's settings into the rig's
%   defaults.
% Parameters
%   ask - true (default) asks before closing a running session. The
%         destructor passes false: an object being destroyed cannot be kept,
%         so there is no Cancel to offer.
arguments
    self
    ask (1,1) logical = true
end
if self.IsClosing
    return
end

running = self.STATE == PRGMSTATE.RUNNING;
if running && ask
    b = questdlg('Experiment is currently running. Closing will stop the experiment.', ...
        'Experiment','Close Experiment','Cancel','Cancel');
    if strcmp(b,'Cancel'), return, end
end

self.IsClosing = true;

% Stop a running session exactly as the Stop control does -- the mode
% broadcast, the timers, the video and the save -- while the window those
% report to still exists.
if running
    try
        self.ExptDispatch("Stop");
    catch ME
        vprintf(0,1,ME);
    end
end

% Whatever is left of the session timer. RUNTIME is an object, so the
% isfield(self.RUNTIME,'TIMER') this used to test was never true, and a
% session closed mid-run kept ticking with its window gone.
if isvalid(self.RUNTIME) && ~isempty(self.RUNTIME.TIMER) && isvalid(self.RUNTIME.TIMER)
    try
        stop(self.RUNTIME.TIMER)
    catch
    end
    try
        delete(self.RUNTIME.TIMER)
    catch
    end
end

% Release hardware as the session closes. Interfaces are kept connected
% across runs for reuse (see epsych.Runtime.delete), so the connection is
% torn down here, at the one point where no rerun follows.
if isa(self.RUNTIME,'epsych.Runtime') && isvalid(self.RUNTIME) && ~isempty(self.RUNTIME.Interfaces)
    for i = 1:numel(self.RUNTIME.Interfaces)
        try
            if isvalid(self.RUNTIME.Interfaces(i)) && self.RUNTIME.Interfaces(i).IsConnected
                self.RUNTIME.Interfaces(i).disconnect();
            end
        catch ME
            vprintf(0,1,ME);
        end
    end
end

% Close the live view before the recorder is deleted so VLC gets the clean
% RC quit rather than being killed with its owner.
self.StopVideoLiveView_;

if ~isempty(self.VlcRecorderSetupGUI_) && isvalid(self.VlcRecorderSetupGUI_)
    try
        delete(self.VlcRecorderSetupGUI_)
    catch
    end
end
if ~isempty(self.VlcRecorder_) && isvalid(self.VlcRecorder_)
    try
        delete(self.VlcRecorder_)
    catch
    end
end

% Closing the session GUI is the one moment the session is known to be over,
% and the point at which the operator is most likely to go and read the log.
granary.Logger.instance().flush();

% Deleting the status bar hands the figure's WindowButtonDownFcn back, which
% gui.components.StatusBar took over for its copy-to-clipboard gesture. It has to happen
% while the figure is still alive for that handover to mean anything.
if isfield(self.H,'statusBar') && ~isempty(self.H.statusBar) && isvalid(self.H.statusBar)
    try
        delete(self.H.statusBar)
    catch
    end
end

if isfield(self.H,'figure1') && isgraphics(self.H.figure1)
    epsych.RunExpt.saveFigurePosition(self.H.figure1.Position);

    try
        self.H.figure1.UserData = [];
        self.H.figure1.CloseRequestFcn = [];
        self.H.figure1.Tag = '';
    catch
    end

    try
        delete(self.H.figure1)
    catch
        self.IsClosing = false;
    end
else
    self.IsClosing = false;
end
