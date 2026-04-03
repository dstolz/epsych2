function PsychTimerStart(self)
% PsychTimerStart — Initialize runtime and optional performance GUI.
% Behavior
%   Updates state, calls TIMERfcn.Start, records StartTime, and
%   attempts to launch BoxFig if configured.


self.STATE = PRGMSTATE.RUNNING;
self.UpdateGUIstate

self.RUNTIME = feval(self.FUNCS.TIMERfcn.Start, self.RUNTIME, self.CONFIG);
self.RUNTIME.StartTime = datetime('now');
vprintf(0,'Experiment started at %s',self.RUNTIME.StartTime)

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

% make all parameters available in TRIALS structure for easy access by trial functions
P = self.RUNTIME.getAllParameters(asStruct = true);
for i = 1:self.RUNTIME.NSubjects
    self.RUNTIME.TRIALS(i).Parameters = P;
end