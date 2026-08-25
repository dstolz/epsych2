classdef SpecSmokeGUI < gui.BehaviorGUI
    % SpecSmokeGUI(RUNTIME)
    % Minimal gui.BehaviorGUI subclass for smoke_test_componentspec.
    %
    % build() deliberately adds nothing: the test drives obj.add itself, so
    % the registry starts empty and every assertion about registration order
    % and count is unambiguous.

    methods
        function obj = SpecSmokeGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name = 'Spec Smoke', ...
                PreferenceTag = 'smokeComponentSpecTest', ...
                DefaultPosition = [100 100 700 500]);
            if nargout == 0, clear obj; end
        end

        function names = registeredNamesForTest(obj)
            % The register names, for the RegisterName assertion.
            names = obj.componentNames();
        end
    end

    methods (Access = protected)
        function build(~, ~)
        end
    end
end
