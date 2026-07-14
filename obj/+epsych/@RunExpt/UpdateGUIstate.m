function UpdateGUIstate(self)
% UpdateGUIstate — Enable/disable controls based on STATE.
% Behavior
%   Centralizes UI state transitions for all major states.
arguments
    self
end

hCtrl = findobj(self.H.figure1,'-regexp','tag','^ctrl')';
set([hCtrl self.H.save_data],'Enable','off')

hSetup = findobj(self.H.figure1,'-regexp','tag','^setup')';

switch self.STATE
    case PRGMSTATE.NOCONFIG
        self.H.modeIndicator.setState(hw.DeviceState.Idle);

    case PRGMSTATE.CONFIGLOADED
        self.STATE = PRGMSTATE.READY;
        set(self.H.view_trials,'Enable','on');
        self.UpdateGUIstate

    case PRGMSTATE.READY
        set([self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')
        self.H.modeIndicator.setState(hw.DeviceState.Standby);

    case PRGMSTATE.RUNNING
        set([self.H.ctrl_pauseall self.H.ctrl_halt],'Enable','on')
        set(hSetup,'Enable','off')

    case PRGMSTATE.POSTRUN

    case PRGMSTATE.STOP
        set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')

    case PRGMSTATE.ERROR
        set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')
        self.H.modeIndicator.setState(hw.DeviceState.Error);
end

% Enable "Assign RUNTIME to Command Window" whenever every connected
% interface is in an active (non-Idle/Error) state. Interfaces is a
% heterogeneous array, so concatenate the per-object modes before testing;
% dot-indexing the array directly yields a comma-separated list that would
% pass multiple arguments to double().
if isempty(self.RUNTIME.Interfaces)
    set(self.H.mnu_assign_runtime,'Enable','off')
else
    modes = double([self.RUNTIME.Interfaces.mode]);
    if all(modes > 0)
        set(self.H.mnu_assign_runtime,'Enable','on')
    else
        set(self.H.mnu_assign_runtime,'Enable','off')
    end
end

