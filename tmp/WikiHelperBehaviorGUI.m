classdef WikiHelperBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass whose only job is to show the helpers the
    % base class provides — addButton, controlColumn, addControl,
    % addUpdateButton, addMonitor — in one screenshot for the wiki's Behavior GUI
    % Components page. Not an example to copy: see
    % examples/customgui/ExampleBehaviorGUI.m for that.

    methods
        function obj = WikiHelperBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='', Visible=false, ...
                PreferenceTag='wikiShotBehaviorGUIHelpers', ...
                DefaultPosition=[200 200 620 225]);
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 2]);
            g.RowHeight   = {40, '1x'};
            g.ColumnWidth = {'1x', '1x'};

            row = uigridlayout(g, [1 3]);
            row.Layout.Row = 1; row.Layout.Column = [1 2];
            row.Padding = [0 0 0 0];
            obj.addButton(row, 'Reward', Text='Manual Reward');
            obj.addButton(row, 'ToneFreq', Type='momentary', Text='Play Tone');

            col = obj.controlColumn(g, Title='Session Controls', Row=2, Column=1);
            obj.addControl(col, 'ToneFreq', Text='Tone Frequency (Hz)');
            obj.addControl(col, 'ToneDur',  Text='Tone Duration (ms)');
            obj.addUpdateButton(col);

            pnl = uipanel(g, 'Title', 'Live Values');
            pnl.Layout.Row = 2; pnl.Layout.Column = 2;
            obj.addMonitor(pnl, {'InTrial','RespCode'}, pollPeriod=0.5);
        end
    end
end
