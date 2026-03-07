function CheckReady(self)
% CheckReady — Evaluate readiness based on subjects and functions.
% Behavior
%   Sets STATE to CONFIGLOADED when both subjects and
%   required functions are defined; otherwise to NOCONFIG.
arguments
    self
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

Subjects = ~isempty(self.CONFIG) && numel(self.CONFIG) > 0 ...
    && isfield(self.CONFIG,'SUBJECT') && ~isempty(self.CONFIG(1).SUBJECT);
Functions = ~isempty(self.FUNCS) && ~any([isempty(self.FUNCS.SavingFcn); ...
    isempty(self.FUNCS.AddSubjectFcn); structfun(@isempty,self.FUNCS.TIMERfcn)]);

isready = Subjects & Functions;
if isready
    self.STATE = PRGMSTATE.CONFIGLOADED;
else
    self.STATE = PRGMSTATE.NOCONFIG;
end

self.UpdateGUIstate
