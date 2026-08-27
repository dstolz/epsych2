function RUNTIME = ep_TimerFcn_Stop(RUNTIME)
% RUNTIME = ep_TimerFcn_Stop(RUNTIME)
% Stop the runtime timer and return the hardware to the idle state.
%
% Parameters:
%	RUNTIME	- Runtime state struct with initialized Interfaces and an EVENTS broadcaster.
%
% Returns:
%	RUNTIME	- Updated runtime state after issuing the idle mode transition.

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS

vprintf(2,'Setting mode to Idle')
set(RUNTIME.Interfaces,'mode',hw.DeviceState.Idle);

RUNTIME.EVENTS.notify('ModeChange',epsych.eventModeChange(hw.DeviceState.Idle));

if ~isempty(RUNTIME.EVENTS) && isvalid(RUNTIME.EVENTS)
	delete(RUNTIME.EVENTS)
end

% Merge each subject's trial journal into its seed .mat so the on-disk
% recovery artifact keeps the layout downstream tools expect. One save call
% per subject — the MAT index is rewritten once per session, not per trial.
for i = 1:numel(RUNTIME.Journal)
    try
        if isvalid(RUNTIME.Journal(i)) && strlength(RUNTIME.Journal(i).FilePath) > 0
            epsych.TrialJournal.mergeToMat(RUNTIME.Journal(i).FilePath, RUNTIME.DataFile(i));
        end
    catch me
        vprintf(0,1,me)
    end
end

% Put the run's log on disk. The file sink buffers everything above its
% FlushLevel, and the end of a run is the point at which the operator may
% read, copy or archive the log.
granary.Logger.instance().flush();