classdef SmokeOutsideComponent < handle
    % SmokeOutsideComponent(RUNTIME, parent, options)
    % A component that knows NOTHING about gui.ComponentSpec, lives outside
    % the gui.components package, and is registered nowhere.
    %
    % It exists to prove the point of the whole mechanism: a lab can write a
    % component of its own and place it with
    %
    %   obj.add('SmokeOutsideComponent', pnl, Color='red')
    %
    % without editing gui.BehaviorGUI, gui.BehaviorBuilder, or any table.
    % The constructor's argument NAMES are what gui.ComponentSpec.forClass
    % reads to work out that RUNTIME goes first and the container second.
    %
    % Used by tmp/smoke_test_componentspec.m.

    properties (SetAccess = private)
        RUNTIME
        PanelH
        LabelH
        Color (1,:) char
    end

    methods
        function obj = SmokeOutsideComponent(RUNTIME, parent, options)
            arguments
                RUNTIME
                parent (1,1)
                options.Color (1,:) char = 'blue'
                options.Text (1,:) char = 'outside component'
            end
            obj.RUNTIME = RUNTIME;
            obj.Color   = options.Color;
            obj.PanelH  = uipanel(parent, 'BorderType', 'none');
            g = uigridlayout(obj.PanelH, [1 1]);
            obj.LabelH  = uilabel(g, 'Text', options.Text, ...
                'FontColor', options.Color);
        end

        function delete(obj)
            if ~isempty(obj.PanelH) && isvalid(obj.PanelH)
                delete(obj.PanelH)
            end
        end
    end
end
