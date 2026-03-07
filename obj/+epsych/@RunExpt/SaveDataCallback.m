function SaveDataCallback(self)
% SaveDataCallback — Invoke SavingFcn with UI-safe control state.
% Behavior
%   Disables controls during save, calls FUNCS.SavingFcn(RUNTIME),
%   and restores GUI state per STATE.
arguments
    self (1,1) ep_RunExpt2
end
oldstate = self.STATE;

try
    hCtrl = findobj(self.H.figure1,'-regexp','tag','^ctrl')';
    set([hCtrl self.H.save_data],'Enable','off')
catch
end

vprintf(3,'SaveDataCallback: Saving via %s',self.FUNCS.SavingFcn)
try
    vprintf(1,'Calling Saving Function: %s',self.FUNCS.SavingFcn)
    feval(self.FUNCS.SavingFcn, self.RUNTIME);
catch me
    vprintf(0,1,me)
end

self.UpdateGUIstate

self.STATE = oldstate;
vprintf(3,'SaveDataCallback: Calling UpdateGUIstate')
self.UpdateGUIstate
