function PsychTimerStart(self)
% PsychTimerStart — Initialize runtime and optional performance GUI.
% Behavior
%   Updates state, calls TIMERfcn.Start, records StartTime, and
%   attempts to launch BehaviorGUI if configured.


self.STATE = PRGMSTATE.RUNNING;
self.UpdateGUIstate

% Call Start timer function to initialize runtime state and selector objects for each subject.
self.RUNTIME = feval(self.FUNCS.TIMERfcn.Start, self.RUNTIME, self.CONFIG);
self.RUNTIME.StartTime = datetime('now');
vprintf(0,'Experiment started at %s',self.RUNTIME.StartTime)

% Attempt to launch BehaviorGUI if configured. This is done after Start so that the live RUNTIME handle is available to the BehaviorGUI function.
if isempty(self.FUNCS.BehaviorGUI)
    vprintf(0,'No Behavior GUI specified')
else
    try
        feval(self.FUNCS.BehaviorGUI, self.RUNTIME);
    catch me
        s = self.FUNCS.BehaviorGUI;
        if ~ischar(s), s = func2str(s); end
        vprintf(0,1,me)
        a = repmat('*',1,50);
        vprintf(0,1,'%s\nFailed to launch behavior performance GUI: %s\n%s',a,s,a)
    end
end

% Notify listeners now that BehaviorGUI is launched and EVENTS is fully initialized.
if self.RUNTIME.isTest
    runMode = hw.DeviceState.Preview;
else
    runMode = hw.DeviceState.Record;
end
self.RUNTIME.EVENTS.notify('ModeChange',epsych.eventModeChange(runMode));