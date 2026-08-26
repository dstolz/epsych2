classdef SessionGateSmokeGUI < gui.BehaviorGUI
    % gui.BehaviorGUI subclass exercised by tmp/smoke_test_sessiongate.m.
    % Calls every add* helper that had no entry point before the session-gate
    % work and keeps what each returned, so the test can assert both halves:
    % the components that build, and the psych-backed ones that must hand
    % back [] instead of throwing when createPsych produced nothing.
    %
    % It deliberately does NOT override createPsych, so obj.Psych is empty.

    properties
        hGate       % addSessionGate
        hScatter    % addScatter
        hClock      % addSessionClock
        hTimer      % addTrialTimer
        hMode       % addModeIndicator
        hHistory    % addHistory     - [] here, no psych object
        hPsychPlot  % addPsychPlot   - [] here, no psych object
        hStair      % addStaircasePlot - [] here, no psych object
    end

    methods
        function obj = SessionGateSmokeGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='Session Gate Smoke', ...
                PreferenceTag='smokeSessionGateTest', ...
                DefaultPosition=[100 100 800 520], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [3 3]);
            g.RowHeight   = {60, '1x', '1x'};
            g.ColumnWidth = {240, '1x', '1x'};

            top = uigridlayout(g, [1 3]);
            top.Layout.Row = 1;
            top.Layout.Column = [1 3];
            obj.hGate = obj.add('gui.components.SessionGate', top);
            obj.hMode = obj.add('gui.components.ModeIndicator', top);
            obj.hTimer = obj.add('gui.components.ElapsedTrialTimer', top);

            obj.hClock = obj.add('gui.components.SessionClock', g);
            obj.hClock.PanelH.Layout.Row = 2;
            obj.hClock.PanelH.Layout.Column = 1;

            pScatter = uipanel(g, 'Title','Scatter');
            pScatter.Layout.Row = 2;
            pScatter.Layout.Column = 2;
            obj.hScatter = obj.add('gui.components.ParameterScatter', pScatter, XParameter='Trial Number');

            % The three psych-backed helpers, against a GUI with no analysis.
            pHist = uipanel(g, 'Title','History');
            pHist.Layout.Row = 2;
            pHist.Layout.Column = 3;
            obj.hHistory = obj.add('gui.components.History', pHist);

            pPlot = uipanel(g, 'Title','Psych Plot');
            pPlot.Layout.Row = 3;
            pPlot.Layout.Column = [1 2];
            obj.hPsychPlot = obj.add('gui.components.PsychPlot', pPlot);

            pStair = uipanel(g, 'Title','Staircase');
            pStair.Layout.Row = 3;
            pStair.Layout.Column = 3;
            obj.hStair = obj.addStaircasePlot(pStair);
        end
    end
end
