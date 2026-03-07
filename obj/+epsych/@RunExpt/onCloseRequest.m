function onCloseRequest(self)
% onCloseRequest — Graceful shutdown of running experiment and UI.
% Behavior
%   Warns if running, stops/deletes timers, resets functions to
%   preferences, and deletes the main figure.
arguments
    self (1,1) ep_RunExpt2
end
if self.STATE == PRGMSTATE.RUNNING
    b = questdlg('Experiment is currently running. Closing will stop the experiment.', ...
        'Experiment','Close Experiment','Cancel','Cancel');
    if strcmp(b,'Cancel'), return, end

    if isfield(self.RUNTIME,'TIMER') && isvalid(timerfind('Name','PsychTimer'))
        stop(self.RUNTIME.TIMER)
        delete(self.RUNTIME.TIMER)
    end
end

self.SetDefaultFuncs(self.FUNCS)

setpref('ep_RunExpt2','FigurePosition',self.H.figure1.Position);

try
    delete(self.H.figure1)
catch
end
