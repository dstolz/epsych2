classdef WikiToolbarBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass whose only job is to show a
    % gui.components.ComponentToolbar in one screenshot for the wiki's Behavior GUI
    % Components page: two lazy tools declared before anything exists, then the
    % separator, then the two registered gui.PopOut components discovered after
    % build returns. Not an example to copy: see
    % examples/customgui/ExampleBehaviorGUI.m for that.
    %
    % The parameter names are the appetitive AM-detection rig's own, because
    % generate_component_screenshots drives this from a real saved session.

    properties
        Toolbar     % gui.components.ComponentToolbar under the shot
    end

    methods
        function obj = WikiToolbarBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='Appetitive AM Detection', Visible=false, ...
                PreferenceTag='wikiShotComponentToolbar', ...
                DefaultPosition=[200 200 660 340]);
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            % Asked for first, yet it still lists what is registered below.
            obj.Toolbar = obj.add('gui.components.ComponentToolbar', fig);

            % Displays this GUI does not show at all: nothing is constructed,
            % so neither the polling timer nor the listeners exist yet.
            obj.Toolbar.addLazyComponent('Performance', ...
                @(c) gui.components.SessionPerformance(obj.RUNTIME, c, ...
                    PreferenceTag='wikiShotToolbarPerf'), ...
                Icon='sessionperformance', WindowSize=[420 260]);
            obj.Toolbar.addLazyComponent('Live Values', ...
                @(c) gui.components.Parameter_Monitor(c, ...
                    [obj.P.InTrial obj.P.RespCode], pollPeriod=1, ...
                    PreferenceTag='wikiShotToolbarMonitor'), ...
                Icon='parametermonitor', WindowSize=[420 220]);

            g = uigridlayout(fig, [1 2]);
            g.ColumnWidth = {'1x', 250};

            obj.register(gui.components.ParameterScatter(obj.RUNTIME, uipanel(g), ...
                PreferenceTag='wikiShotToolbarScatter', ...
                XParameter='TrialIndex', YParameter='StimDelay', ...
                ColorParameter='Response'));

            obj.register(gui.components.NextTrial(obj.RUNTIME, uipanel(g), ...
                Fields=["TrialType","StimDelay","RespWinDur"], ...
                PreferenceTag='wikiShotToolbarNext'), 'Upcoming');
        end
    end
end
