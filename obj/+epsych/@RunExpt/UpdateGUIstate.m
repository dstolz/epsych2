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

    case PRGMSTATE.CONFIGLOADED
        self.STATE = PRGMSTATE.READY;
        set(self.H.view_trials,'Enable','on');
        self.UpdateGUIstate

    case PRGMSTATE.READY
        set([self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')

    case PRGMSTATE.RUNNING
        set([self.H.ctrl_pauseall self.H.ctrl_halt],'Enable','on')
        set(hSetup,'Enable','off')

    case PRGMSTATE.POSTRUN

    case PRGMSTATE.STOP
        set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')

    case PRGMSTATE.ERROR
        set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup']','Enable','on')
end

try
    if double(self.RUNTIME.HW.mode) > 0
        set(self.H.mnu_assign_runtime,'Enable','on')
    else
        set(self.H.mnu_assign_runtime,'Enable','off')
    end
end

