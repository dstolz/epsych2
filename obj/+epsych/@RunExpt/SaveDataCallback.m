function SaveDataCallback(self)
% SaveDataCallback — Invoke SavingFcn with UI-safe control state.
% Behavior
%   Disables controls during save, calls FUNCS.SavingFcn(RUNTIME),
%   and restores GUI state per STATE.
arguments
    self
end
oldstate = self.STATE;

try
    hCtrl = findobj(self.H.figure1,'-regexp','tag','^ctrl')';
    set([hCtrl self.H.save_data],'Enable','off')
end

vprintf(3,'SaveDataCallback: Saving via %s',self.FUNCS.SavingFcn)
try
    if isfield(self.RUNTIME.TRIALS,'DATA')
        vprintf(1,'Calling Saving Function: %s',self.FUNCS.SavingFcn)
        self.setStatus(sprintf('Saving data via %s...',self.FUNCS.SavingFcn))
        feval(self.FUNCS.SavingFcn, self.RUNTIME);
        self.setStatus('Data saved.')
        % Only once the save landed: a registry records the file it finds on
        % disk. A no-op unless one is set up, and never for a Preview.
        epsych.SubjectRegistry.notifySessionSaved(self.RUNTIME, self.CONFIG, self.FUNCS);
    else
        vprintf(0,1,'No data to save!')
        self.setStatus('No data to save.')
    end
catch me
    vprintf(0,1,me)
    self.setStatus(sprintf('Saving data failed: %s',me.message), ...
        'see Help > Diagnostics > Open Current Error Log.')
end

self.UpdateGUIstate

% Whether or not the save worked, the run is over: a registry may send again.
epsych.SubjectRegistry.notifySessionRunning(false);

self.STATE = oldstate;
vprintf(3,'SaveDataCallback: Calling UpdateGUIstate')
self.UpdateGUIstate
