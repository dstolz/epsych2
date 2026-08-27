classdef ModifierButtonBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass exercised by
    % tmp/smoke_test_modifier_buttons.m.
    %
    % The point of the fixture is the injection: addButton declares a
    % ModifierAction and nothing else, and the spec has to supply both the
    % figure's gui.KeyBindings (so the chord arms) and the host (so the
    % press reaches RUNTIME.NOTES) without the paradigm naming either.

    properties
        hReward                       % the addButton result
        AltCount (1,1) double = 0
    end

    methods
        function obj = ModifierButtonBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='ModifierButton BehaviorGUI', ...
                PreferenceTag='modifierButtonGUITest', ...
                DefaultPosition=[100 100 700 450], Visible=false);
            if nargout == 0, clear obj; end
        end

        function countAlt(obj)
            obj.AltCount = obj.AltCount + 1;
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 1]);
            col = obj.controlColumn(g, Title='Triggers', Row=1, Rows=3);

            obj.hReward = obj.addButton(col, '!Reward', ModifierActions = { ...
                'ctrl', @(~,~,~) obj.countAlt(), 'Large Reward'});
        end
    end
end
