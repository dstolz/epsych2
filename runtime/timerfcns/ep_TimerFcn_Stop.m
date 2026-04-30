function RUNTIME = ep_TimerFcn_Stop(RUNTIME)
% RUNTIME = ep_TimerFcn_Stop(RUNTIME)
% 
% Default Stop timer function.
% 

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS

vprintf(2,'Setting mode to Idle')
set(RUNTIME.Interfaces,'mode',hw.DeviceState.Idle);

RUNTIME.HELPER.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Idle));

if ~isempty(RUNTIME.HELPER) && isvalid(RUNTIME.HELPER)
	delete(RUNTIME.HELPER)
end