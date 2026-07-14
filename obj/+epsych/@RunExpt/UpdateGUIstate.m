function UpdateGUIstate(self)
% UpdateGUIstate — Enable/disable controls based on STATE.
% Behavior
%   Centralizes UI state transitions for all major states. Also toggles a
%   distinct figure color/title while a Preview (test) run is RUNNING, and
%   restores the normal appearance for every other state (Stop, Error, or a
%   real Run).
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
        set([self.H.ctrl_run self.H.ctrl_preview hSetup],'Enable','on')
        self.H.modeIndicator.setState(hw.DeviceState.Standby);

    case PRGMSTATE.RUNNING
        set([self.H.ctrl_pauseall self.H.ctrl_halt],'Enable','on')
        set(hSetup,'Enable','off')

    case PRGMSTATE.POSTRUN

    case PRGMSTATE.STOP
        set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup],'Enable','on')

    case PRGMSTATE.ERROR
        set([self.H.save_data self.H.ctrl_run self.H.ctrl_preview hSetup],'Enable','on')
        self.H.modeIndicator.setState(hw.DeviceState.Error);
end

% Distinct figure styling while a Preview (test) run is active, so the
% session window cannot be mistaken for a live Run. This reverts
% automatically for every other STATE (including Stop/Error) and when a
% real Run starts, since RUNTIME.isTest is false in that case.
PREVIEW_COLOR = [0.78 0.87 1.00];
isPreview = self.STATE == PRGMSTATE.RUNNING && self.RUNTIME.isTest;
if isPreview
    self.H.figure1.Color = PREVIEW_COLOR;
    self.H.figure1.Name  = char(self.H.figureBaseName + " — PREVIEW MODE (test run)");
else
    self.H.figure1.Color = self.H.figureDefaultColor;
    self.H.figure1.Name  = char(self.H.figureBaseName);
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

