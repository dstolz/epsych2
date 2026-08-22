classdef NoGateSmokeGUI < gui.BehaviorGUI
    % gui.BehaviorGUI subclass with NO session gate, for the half of
    % tmp/smoke_test_sessiongate.m that checks waitForSessionGate is a no-op
    % rather than an indefinite hold when a paradigm drops the button.

    methods
        function obj = NoGateSmokeGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='No Gate Smoke', ...
                PreferenceTag='smokeNoGateGUITest', ...
                DefaultPosition=[100 100 400 200], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [1 1]);
            obj.addControl(g, 'SmokeFreq', Text='Frequency (Hz)');
        end
    end
end
