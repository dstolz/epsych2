classdef FakeHistoryPsych < psychophysics.Psych
    % Minimal offline psychophysics.Psych subclass for smoke-testing
    % gui.History without a live runtime.

    properties (SetAccess = protected)
        Results = []
    end

    methods
        function obj = FakeHistoryPsych(paramName)
            arguments
                paramName = "Param"
            end
            obj@psychophysics.Psych([], paramName);
        end

        function setData(obj, D)
            % setData(obj, D)
            % Inject fake trial DATA; caller notifies Helper NewData separately.
            obj.DATA = D;
        end

        function appendTrials(obj, D)
            % appendTrials(obj, D)
            % Append trials and broadcast NewData, so listeners are exercised
            % through the same path the runtime uses rather than a direct
            % update() call.
            if isempty(obj.DATA)
                obj.DATA = D;
            else
                obj.DATA = [obj.DATA(:); D(:)]';
            end
            obj.notify_();
        end

        function mutateTrial(obj, k, field, value)
            % mutateTrial(obj, k, field, value)
            % Overwrite one field of an already-recorded trial, to drive the
            % back-fill case that a purely append-based cache must detect.
            obj.DATA(k).(field) = value;
            obj.notify_();
        end

        function notify_(obj)
            % notify_(obj)
            % Broadcast NewData carrying the current DATA, mirroring the
            % payload shape psychophysics.Psych.update_data expects.
            % DATA is wrapped in a cell: struct('DATA',structArray) would
            % build a struct ARRAY, not one struct holding the array.
            % Subject and BoxID are required by the epsych.TrialsData ctor.
            trials = struct('DATA', {obj.DATA}, 'Subject', 'FakeSubject', 'BoxID', 1);
            obj.Helper.notify('NewData', epsych.TrialsData(trials));
        end
    end

    methods (Access = protected)
        function recomputeResults_(~)
        end
    end
end
