function RUNTIME = ep_TimerFcn_Stop(RUNTIME)
% RUNTIME = ep_TimerFcn_Stop(RUNTIME)
% Stop the runtime timer and return the hardware to the idle state.
%
% Parameters:
%	RUNTIME	- Runtime state struct with initialized Interfaces and HELPER objects.
%
% Returns:
%	RUNTIME	- Updated runtime state after issuing the idle mode transition.

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS

vprintf(2,'Setting mode to Idle')
set(RUNTIME.Interfaces,'mode',hw.DeviceState.Idle);

RUNTIME.HELPER.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Idle));

if ~isempty(RUNTIME.HELPER) && isvalid(RUNTIME.HELPER)
	delete(RUNTIME.HELPER)
end