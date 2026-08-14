classdef PumpBoxGUI < gui.BoxGUI
    %PUMPBOXGUI Minimal box GUI for exercising the gui.SyringePump panel.
    %   A gui.SyringePump operator panel beside the two things needed to see
    %   whether it behaves during a session: the trial controls that write
    %   the same pump, and a readout of the reward volume the pump reported
    %   back on every completed trial.
    %
    %   Launch it from a session by naming this class in RunExpt under
    %   Customize > Customize..., Functions tab, Box GUI Function; or run it
    %   without hardware with run_pump_session.
    %
    % See also gui.SyringePump, run_pump_session, create_pump_protocol,
    %          documentation/gui/gui_SyringePump.md

    properties (SetAccess = private)
        Pump = []       % the gui.SyringePump panel under test
    end

    properties (Access = private)
        LastVolumeH_ = []   % per-trial dispensed-volume label
        PrevInfused_ = NaN  % VolumeInfused at the previous trial end
    end

    methods
        function obj = PumpBoxGUI(RUNTIME)
            obj@gui.BoxGUI(RUNTIME, Name = 'Syringe Pump Test Box', ...
                DefaultPosition = [100 100 1120 560]);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)

        function build(obj, fig)
            g = uigridlayout(fig, [2 3]);
            g.ColumnWidth = {320, 260, '1x'};
            g.RowHeight   = {'1x', 170};

            % --- The component under test --------------------------------
            % Options the build method does not state fall back to whatever
            % the operator left behind last session, so only the two things
            % this paradigm actually cares about are passed. With no pump in
            % the protocol the panel makes an offline interface of its own
            % and offers a port to connect on, so this GUI still opens.
            pnl = uipanel(g, 'Title', 'Reward Pump');
            pnl.Layout.Row = [1 2];
            pnl.Layout.Column = 1;
            obj.Pump = obj.addSyringePump(pnl, Rate = 1000, Diameter = 21.59);

            % --- Trial controls ------------------------------------------
            % Rate is a trial-table column, so it is re-asserted on every
            % dispatch. autoCommit writes the operator's edit into the trial
            % table as well as the pump (gui.Parameter_Control's Runtime
            % option), which is what keeps the next dispatch from undoing it.
            col = obj.controlColumn(g, Title = 'Trial Controls', Row = 1, Column = 2);
            obj.addControl(col, 'Rate', autoCommit = true, Text = 'Pump Rate (uL/min)');
            obj.addControl(col, 'ITI',  Text = 'Intertrial Interval (s)');
            obj.addUpdateButton(col);

            obj.LastVolumeH_ = uilabel(col, ...
                'Text', 'No trials yet', ...
                'HorizontalAlignment', 'center', ...
                'FontColor', [0.35 0.35 0.35]);

            % --- Upcoming trial ------------------------------------------
            pnl = uipanel(g, 'Title', 'Next Trial');
            pnl.Layout.Row = 2;
            pnl.Layout.Column = 2;
            obj.addNextTrial(pnl, Fields = ["Volume", "Rate"], FontSize = 14);

            % --- What the pump reported back ------------------------------
            % VolumeInfused is Visible + Access='Read', so the runtime's
            % trial-end sweep queries the pump and lands the accumulated
            % volume in DATA. Plotting it is the proof that path works.
            pnl = uipanel(g, 'Title', 'Cumulative Volume Infused');
            pnl.Layout.Row = 1;
            pnl.Layout.Column = 3;
            obj.register(gui.ParameterScatter(obj.RUNTIME, pnl, ...
                XParameter = 'Trial Number', YParameter = 'VolumeInfused'));

            pnl = uipanel(g, 'Title', 'Pump Readback');
            pnl.Layout.Row = 2;
            pnl.Layout.Column = 3;
            obj.addMonitor(pnl, {'Volume', 'VolumeInfused', 'VolumeWithdrawn'}, ...
                pollPeriod = 1);
        end

        function onNewData(obj, ~, ~)
            % Report the volume this trial actually cost. The pump's
            % accumulators reset on power-up, a diameter change, and at 9999,
            % so the trustworthy quantity is the DIFFERENCE between trials —
            % never the absolute value.
            D = obj.RUNTIME.TRIALS(1).DATA;
            if isempty(D) || ~isfield(D, 'VolumeInfused'), return; end

            infused = D(end).VolumeInfused;
            if isnan(obj.PrevInfused_) || infused < obj.PrevInfused_
                delta = NaN;    % first trial, or the accumulators were zeroed
            else
                delta = infused - obj.PrevInfused_;
            end
            obj.PrevInfused_ = infused;

            if isnan(delta)
                txt = sprintf('Trial %d: %.3f mL total', numel(D), infused);
            else
                txt = sprintf('Trial %d: %.0f uL delivered (%.3f mL total)', ...
                    numel(D), delta * 1000, infused);
            end
            obj.LastVolumeH_.Text = txt;
        end

    end
end
