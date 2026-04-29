function DefineTimerPeriod(self)
% DefineTimerPeriod — Set the PsychTimer period via dialog.
% Prompts for a value in seconds, enforces [0.001, 1] limits, and
% stores the result in FUNCS.TimerPeriod and the ep_RunExpt_TIMER pref.
arguments
    self
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if isfield(self.FUNCS,'TimerPeriod') && ~isempty(self.FUNCS.TimerPeriod)
    current = self.FUNCS.TimerPeriod;
else
    current = 0.01;
end

ontop = self.AlwaysOnTop(false);
a = inputdlg('Timer Period (seconds) [0.001 – 1]','Timer Period',1,{num2str(current)});
self.AlwaysOnTop(ontop);
if isempty(a), return, end

val = str2double(a{1});
if isnan(val) || val < 0.001 || val > 1
    ontop = self.AlwaysOnTop(false);
    errordlg('Timer period must be between 0.001 and 1 seconds.','Timer Period','modal')
    self.AlwaysOnTop(ontop);
    return
end

self.FUNCS.TimerPeriod = val;
setpref('ep_RunExpt_TIMER','Period',val)
vprintf(0,'Timer period set to %.4g s\n',val)
