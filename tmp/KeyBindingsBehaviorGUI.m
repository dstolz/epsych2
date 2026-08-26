classdef KeyBindingsBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass exercised by tmp/smoke_test_keybindings.m.
    %
    % The build order is the point of this fixture: the arrow key is bound
    % FIRST and addUpdateButton is called after it, which is the order that
    % used to leave the binding dead -- gui.components.Parameter_Update claimed the
    % figure's only key callback on its way in.

    properties
        hUpdate         % addUpdateButton result
        hCapture        % addScreenCapture result
        hRegen          % addRegenerateTrial result
        ArrowCount (1,1) double = 0
    end

    methods
        function obj = KeyBindingsBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='KeyBindings BehaviorGUI', ...
                PreferenceTag='keyBindingsGUITest', ...
                DefaultPosition=[100 100 700 450], Visible=false);
            if nargout == 0, clear obj; end
        end

        function countArrow(obj)
            obj.ArrowCount = obj.ArrowCount + 1;
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 1]);

            obj.Keys.bind('leftarrow', @() obj.countArrow(), ...
                Description = 'Respond LEFT', Group = 'Subject response');

            col = obj.controlColumn(g, Title='Controls', Row=1, Rows=5);
            obj.addControl(col, 'SmokeFreq', Text='Frequency (Hz)');
            obj.hUpdate  = obj.addUpdateButton(col);
            obj.hCapture = obj.add('gui.components.ScreenCapture', col);
            obj.hRegen   = obj.add('gui.components.RegenerateTrial', col);
        end
    end
end
