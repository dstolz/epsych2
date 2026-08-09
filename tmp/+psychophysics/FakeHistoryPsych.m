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
    end

    methods (Access = protected)
        function recomputeResults_(~)
        end
    end
end
