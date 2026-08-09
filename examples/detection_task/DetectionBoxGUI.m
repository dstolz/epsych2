classdef DetectionBoxGUI < gui.BoxGUI
    % DetectionBoxGUI  Behavior-box GUI for the worked-example detection task.
    %
    % Goes beyond examples/customgui/ExampleBoxGUI.m by wiring an online
    % analysis pipeline and using every event hook:
    %   - createPsych returns a psychophysics.Detection, which ingests each
    %     trial and re-broadcasts NewData on its own Helper; the base class
    %     automatically makes that Helper this GUI's NewData source, so
    %     onNewData always sees an up-to-date Psych object.
    %   - gui.PsychPlot draws the live d' curve from the same Detection.
    %   - onNewTrial announces the upcoming trial from the event payload.
    %   - onNewData refreshes a per-level performance table and session tally.
    %   - onModeChange tracks Preview/Record/Pause/Stop in the header.
    %
    % Launch in a real session by setting Customize > Customize..., Functions
    % tab, "Box GUI Function:" to DetectionBoxGUI (the class must be on the
    % path). Try it without hardware: run_detection_session (same folder).
    %
    % Walkthrough: documentation/examples/Detection_Task_3_BoxGUI.md
    %
    % See also gui.BoxGUI, psychophysics.Detection, gui.PsychPlot

    properties (SetAccess = private)
        ModeLabel    matlab.ui.control.Label
        TrialLabel   matlab.ui.control.Label
        TallyLabel   matlab.ui.control.Label
        SummaryTable matlab.ui.control.Table
    end

    methods
        function obj = DetectionBoxGUI(RUNTIME)
            obj@gui.BoxGUI(RUNTIME, Name = 'Tone Detection Box', ...
                DefaultPosition = [100 100 1150 700]);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function p = createPsych(obj, R)
            % Track go-trial performance against ToneLevel. Runs before the
            % figure exists; return [] to fall back to RUNTIME.HELPER events.
            p = [];
            if isfield(obj.P, 'ToneLevel')
                p = psychophysics.Detection(R, obj.P.ToneLevel, ...
                    epsych.BitMask.TrialType_0);
            end
        end

        function build(obj, fig)
            g = uigridlayout(fig, [4 3]);
            g.RowHeight   = {26, 55, '1x', '1x'};
            g.ColumnWidth = {300, '1x', '1x'};

            % Header: session mode, upcoming trial, running tally
            obj.ModeLabel = uilabel(g, Text = 'Mode: -', FontWeight = 'bold');
            obj.ModeLabel.Layout.Row = 1; obj.ModeLabel.Layout.Column = 1;
            obj.TrialLabel = uilabel(g, Text = 'Waiting for first trial...');
            obj.TrialLabel.Layout.Row = 1; obj.TrialLabel.Layout.Column = 2;
            obj.TallyLabel = uilabel(g, Text = '', HorizontalAlignment = 'right');
            obj.TallyLabel.Layout.Row = 1; obj.TallyLabel.Layout.Column = 3;

            % Trigger buttons across the top
            row = uigridlayout(g, [1 4]);
            row.Layout.Row = 2; row.Layout.Column = [1 3];
            obj.addButton(row, 'Reward', Text = 'Manual Reward');

            % Editable parameters, committed together by the update button
            col = obj.controlColumn(g, Title = 'Session Controls', ...
                Row = [3 4], Column = 1);
            obj.addControl(col, 'ToneFreq');
            obj.addControl(col, 'ToneDur');
            obj.addControl(col, 'RewardVol');
            obj.addUpdateButton(col);

            % Live read-back values
            pnl = uipanel(g, 'Title', 'Live Values');
            pnl.Layout.Row = 3; pnl.Layout.Column = 2;
            obj.addMonitor(pnl, {'InTrial', 'RespCode'}, pollPeriod = 0.5);

            % Per-level performance, refreshed by onNewData
            pnl = uipanel(g, 'Title', 'Performance by Level');
            pnl.Layout.Row = 4; pnl.Layout.Column = 2;
            inner = uigridlayout(pnl, [1 1]);
            inner.Padding = [0 0 0 0];
            obj.SummaryTable = uitable(inner);
            obj.SummaryTable.ColumnName = {'Level (dB SPL)', '# Go', 'Hit %', 'd'''};

            % Live psychometric summary. gui.PsychPlot needs a classic axes
            % (not uiaxes); axes() inside a uifigure panel provides one.
            pnl = uipanel(g, 'Title', 'Detection Performance');
            pnl.Layout.Row = [3 4]; pnl.Layout.Column = 3;
            if ~isempty(obj.Psych)
                ax = axes(pnl);
                obj.register(gui.PsychPlot(obj.Psych, ax));
            end
        end

        function onNewTrial(obj, ~, event)
            % Announce the trial that was just dispatched. event.Data is the
            % TRIALS struct: NextTrialID indexes the compiled condition list,
            % writeParamIdx maps parameter names to its columns.
            T   = event.Data;
            lvl = T.trials{T.NextTrialID, T.writeParamIdx.ToneLevel};
            tt  = T.trials{T.NextTrialID, T.writeParamIdx.TrialType};
            if tt == 0
                obj.TrialLabel.Text = sprintf('Trial %d: GO - tone at %g dB SPL', ...
                    T.TrialIndex, lvl);
            else
                obj.TrialLabel.Text = sprintf('Trial %d: NO-GO - silent catch', ...
                    T.TrialIndex);
            end
        end

        function onNewData(obj, ~, ~)
            % obj.Psych ingested the completed trial before this hook ran
            % (its Helper is this GUI's NewData source), so its dependent
            % properties already reflect the new trial.
            P = obj.Psych;
            if isempty(P) || isempty(P.DATA), return; end

            obj.TallyLabel.Text = sprintf('%d trials | %d hits | %d false alarms', ...
                P.NumTrials, sum(P.Hit_Ind), sum(P.FA_Ind));

            P.targetTrialType = epsych.BitMask.TrialType_0;
            uv = P.uniqueValues;
            if isempty(uv), return; end
            S = [compose("%g", uv(:)), ...
                 compose("%d", [P.Count.TrialType_0].'), ...
                 compose("%.0f", 100 * P.Hit_Rate(:)), ...
                 compose("%.2f", P.DPrime(:))];
            obj.SummaryTable.Data = flipud(S); % loudest level first
        end

        function onModeChange(obj, ~, event)
            % event.NewMode is an hw.DeviceState.
            obj.ModeLabel.Text = "Mode: " + event.NewMode.asString();
            if event.NewMode == hw.DeviceState.Record
                obj.ModeLabel.FontColor = [0 0.5 0];
            elseif event.NewMode.isIdle()
                obj.ModeLabel.FontColor = [0.6 0.1 0.1];
            else
                obj.ModeLabel.FontColor = [0 0 0];
            end
        end

        function onFirstTrial(obj, ~, ~)
            % Runs once, at the first NewTrial after build() completed.
            vprintf(2, '%s: session started', class(obj))
        end
    end
end
