classdef OnlinePlotBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass exercising addOnlinePlot, used by
    % tmp/smoke_test_onlineplot_dialogs.m. It builds one configured plot, one
    % that must be refused for having no Source, and a component toolbar the
    % registered plot has to reach.

    properties
        Plot     % addOnlinePlot result
        Blank    % addOnlinePlot with no Source; must be []
        Toolbar  % addComponentToolbar result
    end

    methods
        function obj = OnlinePlotBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='OnlinePlot BehaviorGUI', ...
                PreferenceTag='OnlinePlotBehaviorGUI', ...
                DefaultPosition=[100 100 760 420], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            obj.Toolbar = obj.add('gui.components.ComponentToolbar', fig);

            g = uigridlayout(fig, [1 1]);
            p = uipanel(g, 'Title', 'Activity');
            p.Layout.Row = 1;
            p.Layout.Column = 1;

            obj.Plot = obj.add('gui.components.OnlinePlot', p, ...
                Source={'Trace01','Trace02'}, ...
                TimeWindow=[-20 5], ...
                PreferenceTag='OnlinePlotBehaviorGUI_Main');

            obj.Blank = obj.add('gui.components.OnlinePlot', p); % no Source: must be refused
        end
    end
end
