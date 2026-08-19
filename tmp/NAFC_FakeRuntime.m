classdef NAFC_FakeRuntime < handle
    % Minimal epsych.Runtime stand-in for psychophysics.NAFC online-mode
    % smoke tests: the EVENTS broadcaster plus a settable TRIALS struct,
    % published the way ep_TimerFcn_RunTime publishes a completed trial.

    properties
        EVENTS
        TRIALS = []
    end

    methods
        function obj = NAFC_FakeRuntime()
            obj.EVENTS = epsych.EventHub;
        end

        function push(obj, DATA)
            % push(obj, DATA)
            % Publish the per-trial DATA array as a NewData event.
            obj.TRIALS = struct( ...
                'DATA',       DATA, ...
                'Subject',    struct('Name', 'FakeSubject'), ...
                'BoxID',      1, ...
                'TrialIndex', numel(DATA));
            obj.EVENTS.notify('NewData', epsych.TrialsData(obj.TRIALS));
        end
    end
end
