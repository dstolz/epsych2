function PsychTimerStart(self)
% PsychTimerStart — Initialize runtime and optional performance GUI.
% Behavior
%   Updates state, calls TIMERfcn.Start, records StartTime, attempts to
%   launch BehaviorGUI if configured, broadcasts the run mode, and then
%   starts the webcam recording when one was asked for.


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

% Record last, once the behavior GUI is up and showing run mode: launching VLC
% blocks for about a second and takes the foreground, so starting it earlier
% held back the window the operator actually watches the session on. The cost
% is that the first moment of the run is not filmed. Preview never records;
% StartVideoRecording_ checks the "Record video" toggle itself and reports its
% own failures rather than throwing, so a camera problem cannot end the run.
if ~self.RUNTIME.isTest
    drawnow % paint the behavior GUI before VLC takes the foreground
    % Both the drawnow and VLC's own launch yield, so a trial tick that
    % auto-stops the session (idle hardware) can land here while this
    % callback is still on the stack. PsychTimerStop has then already run
    % its StopVideoRecording_, and a recording started now would outlive
    % the run with nothing left to finalize it.
    if self.STATE == PRGMSTATE.RUNNING
        self.StartVideoRecording_
    end
end