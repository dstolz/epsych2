function onCloseRequest(self)
% onCloseRequest — Graceful shutdown of running experiment and UI.
% Behavior
%   Warns if running, stops/deletes timers, resets functions to
%   preferences, and deletes the main figure.
arguments
    self
end
if self.IsClosing
    return
end

if self.STATE == PRGMSTATE.RUNNING
    b = questdlg('Experiment is currently running. Closing will stop the experiment.', ...
        'Experiment','Close Experiment','Cancel','Cancel');
    if strcmp(b,'Cancel'), return, end
end

self.IsClosing = true;

if isfield(self.RUNTIME,'TIMER') && ~isempty(self.RUNTIME.TIMER) && isvalid(self.RUNTIME.TIMER)
    try
        stop(self.RUNTIME.TIMER)
    catch
    end
    try
        delete(self.RUNTIME.TIMER)
    catch
    end
end

self.SetDefaultFuncs(self.FUNCS)

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
