classdef ScreenCaptureSmokeGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass exercised by tmp/smoke_test_screen_capture.m.
    % Hosts one addScreenCapture button, so the test can assert that the helper
    % targets this GUI's figure and that closing the GUI takes the component —
    % and its confirmation timer — with it.

    properties
        Capture      % gui.components.ScreenCapture built by addScreenCapture
    end

    methods
        function obj = ScreenCaptureSmokeGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='Screen Capture BehaviorGUI', ...
                PreferenceTag='smokeScreenCaptureBehaviorGUI', ...
                DefaultPosition=[100 100 600 400], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 1]);
            g.RowHeight = {30, '1x'};

            obj.Capture = obj.add('gui.components.ScreenCapture', g, Text='Screenshot');
            obj.Capture.Button.Layout.Row = 1;

            lbl = uilabel(g, 'Text', 'Session content', 'FontSize', 20, ...
                'HorizontalAlignment', 'center');
            lbl.Layout.Row = 2;
        end
    end
end
