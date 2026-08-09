function T = CreateTimer(self)
% CreateTimer — Build (or rebuild) the main PsychTimer.
% Output
%   T — MATLAB timer object configured for the runtime loop.
arguments
    self
end
T = timerfindall('Name','PsychTimer');
if ~isempty(T)
    stop(T)
    delete(T)
end

if isfield(self.FUNCS,'TimerPeriod') && ~isempty(self.FUNCS.TimerPeriod)
    period = self.FUNCS.TimerPeriod;
else
    period = 0.01;
end

T = timer('BusyMode','drop', ...
    'ExecutionMode','fixedSpacing', ...
    'Name','PsychTimer', ...
    'Period',period, ...
    'StartFcn',@(~,~) self.PsychTimerStart, ...
    'TimerFcn',@(~,~) self.PsychTimerRunTime, ...
    'ErrorFcn',@(~,~) self.PsychTimerError, ...
    'StopFcn', @(~,~) self.PsychTimerStop, ...
    'TasksToExecute',inf);
