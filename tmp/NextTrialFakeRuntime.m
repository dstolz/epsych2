classdef NextTrialFakeRuntime < handle
    % Minimal epsych.Runtime stand-in for gui.NextTrial smoke tests:
    % the EVENTS broadcaster plus a TRIALS struct shaped like the one
    % ep_TimerFcn_Start builds (parameters, trials, writeparams,
    % writeParamIdx, NextTrialID).

    properties
        EVENTS
        TRIALS = struct([])
    end

    methods
        function obj = NextTrialFakeRuntime()
            obj.EVENTS = epsych.EventHub;
        end
    end
end
