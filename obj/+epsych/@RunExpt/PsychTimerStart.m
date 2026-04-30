function PsychTimerStart(self)
% PsychTimerStart — Initialize runtime and optional performance GUI.
% Behavior
%   Updates state, calls TIMERfcn.Start, records StartTime, and
%   attempts to launch BoxFig if configured.


self.STATE = PRGMSTATE.RUNNING;
self.UpdateGUIstate

% Call Start timer function to initialize runtime state and selector objects for each subject.
self.RUNTIME = feval(self.FUNCS.TIMERfcn.Start, self.RUNTIME, self.CONFIG);
self.RUNTIME.StartTime = datetime('now');
vprintf(0,'Experiment started at %s',self.RUNTIME.StartTime)

% Attempt to launch BoxFig if configured. This is done after Start so that the live RUNTIME handle is available to the BoxFig function.
if isempty(self.FUNCS.BoxFig)
    vprintf(0,'No Behavior GUI specified')
else
    try
        feval(self.FUNCS.BoxFig, self.RUNTIME);
    catch me
        s = self.FUNCS.BoxFig;
        if ~ischar(s), s = func2str(s); end
        vprintf(0,1,me)
        a = repmat('*',1,50);
        vprintf(0,1,'%s\nFailed to launch behavior performance GUI: %s\n%s',a,s,a)
    end
end

% Notify listeners now that BoxFig is launched and HELPER is fully initialized.
self.RUNTIME.HELPER.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Record));