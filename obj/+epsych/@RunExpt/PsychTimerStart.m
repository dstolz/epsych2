function PsychTimerStart(self)
% PsychTimerStart — Initialize runtime and optional performance GUI.
% Behavior
%   Updates state, calls TIMERfcn.Start, records StartTime, and
%   attempts to launch BoxFig if configured.
arguments
    self (1,1) ep_RunExpt2
end
self.STATE = PRGMSTATE.RUNNING;
self.UpdateGUIstate

self.RUNTIME = feval(self.FUNCS.TIMERfcn.Start, self.RUNTIME, self.CONFIG);
self.RUNTIME.StartTime = datetime('now');
vprintf(0,'Experiment started at %s',self.RUNTIME.StartTime)

if isempty(self.FUNCS.BoxFig)
    vprintf(2,'No Behavior Performance GUI specified')
else
    try
        feval(self.FUNCS.BoxFig, self.RUNTIME);
        set(self.H.mnu_LaunchGUI,'Enable','on')
    catch me
        s = self.FUNCS.BoxFig;
        if ~ischar(s), s = func2str(s); end
        vprintf(0,1,me)
        a = repmat('*',1,50);
        set(self.H.mnu_LaunchGUI,'Enable','off')
        vprintf(0,1,'%s\nFailed to launch behavior performance GUI: %s\n%s',a,s,a)
    end
end
