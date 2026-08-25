classdef PopOutBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass exercised by tmp/smoke_test_popout.m.
    % Hosts one poppable component and the addPopOutButton that opens it,
    % so the test can assert that a button press opens a pop-out window and
    % that closing the GUI takes that window with it.

    properties
        Scatter      % gui.components.ParameterScatter built into the GUI
        PopButton    % addPopOutButton result
    end

    methods
        function obj = PopOutBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='Pop Out BehaviorGUI', ...
                PreferenceTag='smokePopOutBehaviorGUI', ...
                DefaultPosition=[100 100 700 450], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 1]);
            g.RowHeight = {30, '1x'};

            p = uipanel(g);
            p.Layout.Row = 2;
            obj.Scatter = obj.register(gui.components.ParameterScatter(obj.RUNTIME, p, ...
                PreferenceTag='smokePopOutScatter'));

            obj.PopButton = obj.addPopOutButton(g, obj.Scatter, Text='Scatter...');
            obj.PopButton.Layout.Row = 1;
        end
    end
end
