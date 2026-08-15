classdef ExampleBehaviorGUI < gui.BehaviorGUI
    %EXAMPLEBEHAVIORGUI Copyable template for a custom experiment GUI.
    %   Subclass gui.BehaviorGUI, lay out your controls in build(), and the base
    %   class provides lifecycle, listeners, position persistence, and
    %   teardown. Point a project at this class via Subjects > Subjects &
    %   Projects, Project > Edit Project..., Behavior GUI field ("ExampleBehaviorGUI");
    %   it launches at session start for that project's subjects.
    %
    %   Try it without hardware: examples/customgui/run_example.m
    %
    % See also gui.BehaviorGUI, documentation/gui/gui_BehaviorGUI.md

    methods
        function obj = ExampleBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='Example Task', ...
                DefaultPosition=[100 100 1100 650]);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function p = createPsych(obj, R)
            % Optional: track behavior with a psychophysics object; its
            % Events broadcaster becomes the GUI's NewData source. Return [] to listen
            % to RUNTIME.EVENTS directly.
            p = [];
            if isfield(obj.P, 'Depth')
                p = psychophysics.Staircase(R, obj.P.Depth);
            end
        end

        function build(obj, fig)
            g = uigridlayout(fig, [3 3]);
            g.RowHeight   = {60, '1x', '1x'};
            g.ColumnWidth = {300, '1x', '1x'};

            % Trigger buttons across the top
            row = uigridlayout(g, [1 4]);
            row.Layout.Row = 1; row.Layout.Column = [1 3];
            obj.addButton(row, 'DropPellet', Text='Pellet');
            obj.addButton(row, '~TrialDelivery', Text='Deliver Trials');

            % Editable parameters: one line each. Names that do not exist
            % in the loaded protocol are skipped silently.
            col = obj.controlColumn(g, Title='Trial Controls', Row=[2 3], Column=1);
            obj.addControl(col, 'ITIDur',     Text='Intertrial Interval (s)');
            obj.addControl(col, 'TimeoutDur', Text='Timeout Duration (s)');
            obj.addControl(col, 'Depth',      Text='Modulation Depth (%)');
            obj.addControl(col, 'dBSPL',      Text='Sound Level (dB SPL)');
            obj.addUpdateButton(col); % commits every control above

            % Live read-only display
            p = uipanel(g, 'Title', 'Monitor');
            p.Layout.Row = 2; p.Layout.Column = 2;
            obj.addMonitor(p, {'InTrial','RespCode','TrialCount'}, pollPeriod=0.5);

            % Any other component: construct natively, register for teardown
            p = uipanel(g, 'Title', 'Trial History');
            p.Layout.Row = 3; p.Layout.Column = 2;
            obj.register(gui.ParameterScatter(obj.RUNTIME, p, ...
                XParameter='Trial Number', YParameter='Depth'));

            ax = uiaxes(g);
            ax.Layout.Row = [2 3]; ax.Layout.Column = 3;
            if ~isempty(obj.Psych)
                obj.Psych.Plot(ax);
            end
        end

        function onNewData(obj, ~, ~)
            % Per-trial updates go here; obj.Psych has already processed
            % the trial when this runs.
            vprintf(2, '%s: trial completed', class(obj))
        end
    end
end
