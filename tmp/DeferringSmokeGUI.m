classdef DeferringSmokeGUI < gui.BehaviorGUI
    % g = DeferringSmokeGUI(RUNTIME)
    % The smallest behavior GUI that asks for its displays to draw after the
    % next trial is dispatched (gui.BehaviorGUI.deferDisplayWork). Test
    % support for tmp/smoke_test_eventhub_deferral.m; it builds nothing.

    methods
        function obj = DeferringSmokeGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name = 'Deferring Smoke GUI', ...
                PreferenceTag = 'smokeDeferringGUI', Visible = false);
        end
    end

    methods (Access = protected)
        function build(~, ~)
        end

        function tf = deferDisplayWork(~)
            tf = true;
        end
    end
end
