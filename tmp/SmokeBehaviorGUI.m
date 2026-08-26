classdef SmokeBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass exercised by tmp/smoke_test_behaviorgui.m.
    % Exposes the components it creates and counts hook invocations so the
    % test can assert on construction, event dispatch, and teardown.

    properties
        hPelletBtn      % momentary addButton result
        hToggleBtn      % toggle addButton result
        hFreq           % addControl result
        hLevel          % addControl result
        hMissing        % addControl result for a nonexistent parameter
        hUpdate         % addUpdateButton result
        hMon            % addMonitor result

        NewTrialCount (1,1) double = 0
        NewDataCount (1,1) double = 0
        ModeChangeCount (1,1) double = 0
        FirstTrialCount (1,1) double = 0
        DeferredRan (1,1) logical = false
    end

    methods
        function obj = SmokeBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='Smoke BehaviorGUI', ...
                PreferenceTag='smokeBehaviorGUITest', ...
                DefaultPosition=[100 100 700 450], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 2]);
            g.RowHeight = {60, '1x'};
            g.ColumnWidth = {'1x', '1x'};

            row = uigridlayout(g, [1 2]);
            row.Layout.Row = 1;
            row.Layout.Column = [1 2];
            obj.hPelletBtn = obj.addButton(row, 'SmokePellet', Text='Pellet');
            obj.hToggleBtn = obj.addButton(row, '~SmokeToggle', Text='Toggle');

            col = obj.controlColumn(g, Title='Controls', Row=2, Column=1, Rows=5);
            obj.hFreq    = obj.addControl(col, 'SmokeFreq', Text='Frequency (Hz)');
            obj.hLevel   = obj.addControl(col, 'SmokeLevel');
            obj.hMissing = obj.addControl(col, 'DoesNotExist');
            obj.hUpdate  = obj.addUpdateButton(col);

            p = uipanel(g, 'Title', 'Monitor');
            p.Layout.Row = 2;
            p.Layout.Column = 2;
            obj.hMon = obj.add('gui.components.Parameter_Monitor', p, 'Parameters', {'SmokeState','AlsoMissing'}, pollPeriod=0.2);

            obj.defer(@() obj.markDeferred);
        end

        function onNewTrial(obj, ~, ~)
            obj.NewTrialCount = obj.NewTrialCount + 1;
        end

        function onNewData(obj, ~, ~)
            obj.NewDataCount = obj.NewDataCount + 1;
        end

        function onModeChange(obj, ~, ~)
            obj.ModeChangeCount = obj.ModeChangeCount + 1;
        end

        function onFirstTrial(obj, ~, ~)
            obj.FirstTrialCount = obj.FirstTrialCount + 1;
        end
    end

    methods
        function markDeferred(obj)
            obj.DeferredRan = true;
        end
    end
end
