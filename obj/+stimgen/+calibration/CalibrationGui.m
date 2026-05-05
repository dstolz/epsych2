classdef CalibrationGui < handle
    % gui = stimgen.calibration.CalibrationGui()
    % gui = stimgen.calibration.CalibrationGui(Adapter=adapter)
    % gui = stimgen.calibration.CalibrationGui(Engine=eng)
    % Interactive GUI for the stimgen.calibration package.
    %
    % Provides user parameterization of calibration settings, live inspection of
    % the latest response waveform/spectrum, transfer-curve visualization for
    % tone and click calibration tables, and save/load support for .esgc files.
    %
    % Parameters:
    %   Adapter - (optional) stimgen.calibration.HwAdapter used for live runs.
    %   Engine  - (optional) existing stimgen.calibration.Engine instance.
    %
    % Returns:
    %   gui - GUI controller handle.
    %
    % Example:
    %   adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW);
    %   gui = stimgen.calibration.CalibrationGui(Adapter=adapter);
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.InterfaceAdapter,
    %           documentation/stimgen/stimgen_CalibrationGui.md,
    %           documentation/stimgen/stimgen_calibration.md

    properties (SetAccess = private)
        Engine stimgen.calibration.Engine
    end

    properties (Access = private)
        Figure
        Grid

        % Controls
        RefLevelField
        RefFreqField
        MicSensField
        NormativeField
        ExcitationField
        ShowLivePlotsCheck
        ToneFreqsField
        ClickDurationsField
        StatusLabel

        % Buttons
        BtnReference
        BtnTones
        BtnClicks
        BtnFilter
        BtnSave
        BtnLoad

        % Axes
        AxTime
        AxSpectrum
        AxTransfer
    end

    methods
        function obj = CalibrationGui(options)
            % obj = stimgen.calibration.CalibrationGui(options)
            % Construct and display the calibration GUI.
            arguments
                options.Adapter = []
                options.Engine = []
            end

            if ~isempty(options.Engine)
                obj.Engine = options.Engine;
            elseif ~isempty(options.Adapter)
                obj.Engine = stimgen.calibration.Engine(options.Adapter);
            else
                obj.Engine = stimgen.calibration.Engine();
            end

            obj.build_ui_();
            obj.sync_controls_();
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
        end

        function show(obj)
            % show(obj)
            % Bring the GUI window to the foreground.
            if isvalid(obj.Figure)
                figure(obj.Figure);
            end
        end

        function set_adapter(obj, adapter)
            % set_adapter(obj, adapter)
            % Attach/replace the hardware adapter used for live calibration.
            arguments
                obj
                adapter (1,1) stimgen.calibration.HwAdapter
            end
            obj.Engine.Adapter = adapter;
            obj.update_runtime_state_();
            obj.set_status_('Adapter attached. Ready for live calibration.', false);
        end
    end

    methods (Access = private)
        function build_ui_(obj)
            obj.Figure = uifigure( ...
                Name='Stim Calibration', ...
                Position=[120 80 1320 760]);

            obj.Grid = uigridlayout(obj.Figure, [1 2]);
            obj.Grid.ColumnWidth = {360, '1x'};
            obj.Grid.RowHeight = {'1x'};

            obj.build_controls_panel_();
            obj.build_plots_panel_();
        end

        function build_controls_panel_(obj)
            panel = uipanel(obj.Grid, Title='Controls');
            panel.Layout.Row = 1;
            panel.Layout.Column = 1;

            g = uigridlayout(panel, [15 2]);
            g.RowHeight = {24, 24, 24, 24, 24, 24, 24, 70, 70, 30, 30, 30, 30, 30, '1x'};
            g.ColumnWidth = {'1x', '1x'};

            refLevelLabel = uilabel(g, Text='Reference Level (dB SPL)', HorizontalAlignment='right');
            refLevelLabel.Layout.Row = 1;
            refLevelLabel.Layout.Column = 1;
            obj.RefLevelField = uieditfield(g, 'numeric');
            obj.RefLevelField.Layout.Row = 1;
            obj.RefLevelField.Layout.Column = 2;
            obj.RefLevelField.Limits = [1, 160];
            obj.RefLevelField.ValueDisplayFormat = '%.1f';

            refFreqLabel = uilabel(g, Text='Reference Frequency (Hz)', HorizontalAlignment='right');
            refFreqLabel.Layout.Row = 2;
            refFreqLabel.Layout.Column = 1;
            obj.RefFreqField = uieditfield(g, 'numeric');
            obj.RefFreqField.Layout.Row = 2;
            obj.RefFreqField.Layout.Column = 2;
            obj.RefFreqField.Limits = [20, 200000];
            obj.RefFreqField.ValueDisplayFormat = '%.1f';

            micSensLabel = uilabel(g, Text='Mic Sensitivity (V/Pa)', HorizontalAlignment='right');
            micSensLabel.Layout.Row = 3;
            micSensLabel.Layout.Column = 1;
            obj.MicSensField = uieditfield(g, 'numeric');
            obj.MicSensField.Layout.Row = 3;
            obj.MicSensField.Layout.Column = 2;
            obj.MicSensField.Limits = [eps, 100];
            obj.MicSensField.ValueDisplayFormat = '%.5f';

            normativeLabel = uilabel(g, Text='Normative Value (dB SPL)', HorizontalAlignment='right');
            normativeLabel.Layout.Row = 4;
            normativeLabel.Layout.Column = 1;
            obj.NormativeField = uieditfield(g, 'numeric');
            obj.NormativeField.Layout.Row = 4;
            obj.NormativeField.Layout.Column = 2;
            obj.NormativeField.Limits = [1, 180];
            obj.NormativeField.ValueDisplayFormat = '%.1f';

            excitationLabel = uilabel(g, Text='Excitation Voltage (V)', HorizontalAlignment='right');
            excitationLabel.Layout.Row = 5;
            excitationLabel.Layout.Column = 1;
            obj.ExcitationField = uieditfield(g, 'numeric');
            obj.ExcitationField.Layout.Row = 5;
            obj.ExcitationField.Layout.Column = 2;
            obj.ExcitationField.Limits = [eps, 10];
            obj.ExcitationField.ValueDisplayFormat = '%.3f';

            showPlotsLabel = uilabel(g, Text='Show Engine Live Plots', HorizontalAlignment='right');
            showPlotsLabel.Layout.Row = 6;
            showPlotsLabel.Layout.Column = 1;
            obj.ShowLivePlotsCheck = uicheckbox(g, Text='');
            obj.ShowLivePlotsCheck.Layout.Row = 6;
            obj.ShowLivePlotsCheck.Layout.Column = 2;

            toneFreqsLabel = uilabel(g, Text='Tone Frequencies (Hz)', HorizontalAlignment='right');
            toneFreqsLabel.Layout.Row = 7;
            toneFreqsLabel.Layout.Column = 1;
            obj.ToneFreqsField = uitextarea(g);
            obj.ToneFreqsField.Layout.Row = 8;
            obj.ToneFreqsField.Layout.Column = [1 2];
            obj.ToneFreqsField.Value = {'(empty = default log sweep)', 'example: 250,500,1000,2000,4000,8000'};

            clickDurationsLabel = uilabel(g, Text='Click Durations (s)', HorizontalAlignment='right');
            clickDurationsLabel.Layout.Row = 9;
            clickDurationsLabel.Layout.Column = 1;
            obj.ClickDurationsField = uitextarea(g);
            obj.ClickDurationsField.Layout.Row = 9;
            obj.ClickDurationsField.Layout.Column = 2;
            obj.ClickDurationsField.Value = {'(empty = default 1..128 samples)', 'example: 1e-5,2e-5,4e-5,8e-5'};

            obj.BtnReference = uibutton(g, Text='Measure Reference', ...
                ButtonPushedFcn=@(~,~) obj.on_measure_reference_());
            obj.BtnReference.Layout.Row = 10;
            obj.BtnReference.Layout.Column = [1 2];

            obj.BtnTones = uibutton(g, Text='Calibrate Tones', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_tones_());
            obj.BtnTones.Layout.Row = 11;
            obj.BtnTones.Layout.Column = [1 2];

            obj.BtnClicks = uibutton(g, Text='Calibrate Clicks', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_clicks_());
            obj.BtnClicks.Layout.Row = 12;
            obj.BtnClicks.Layout.Column = [1 2];

            obj.BtnFilter = uibutton(g, Text='Design Filter', ...
                ButtonPushedFcn=@(~,~) obj.on_design_filter_());
            obj.BtnFilter.Layout.Row = 13;
            obj.BtnFilter.Layout.Column = [1 2];

            row14 = uigridlayout(g, [1 2]);
            row14.Layout.Row = 14;
            row14.Layout.Column = [1 2];
            row14.ColumnWidth = {'1x','1x'};

            obj.BtnLoad = uibutton(row14, Text='Load .esgc', ...
                ButtonPushedFcn=@(~,~) obj.on_load_());
            obj.BtnLoad.Layout.Row = 1;
            obj.BtnLoad.Layout.Column = 1;
            obj.BtnSave = uibutton(row14, Text='Save .esgc', ...
                ButtonPushedFcn=@(~,~) obj.on_save_());
            obj.BtnSave.Layout.Row = 1;
            obj.BtnSave.Layout.Column = 2;

            obj.StatusLabel = uilabel(g, Text='Ready.', HorizontalAlignment='left');
            obj.StatusLabel.Layout.Row = 15;
            obj.StatusLabel.Layout.Column = [1 2];
        end

        function build_plots_panel_(obj)
            panel = uipanel(obj.Grid, Title='Visualization');
            panel.Layout.Row = 1;
            panel.Layout.Column = 2;

            g = uigridlayout(panel, [2 2]);
            g.RowHeight = {'1x', '1x'};
            g.ColumnWidth = {'1x', '1x'};

            obj.AxTime = uiaxes(g);
            obj.AxTime.Layout.Row = 1;
            obj.AxTime.Layout.Column = 1;
            title(obj.AxTime, 'Temporal Response');
            xlabel(obj.AxTime, 'Time (s)');
            ylabel(obj.AxTime, 'V');
            grid(obj.AxTime, 'on');

            obj.AxSpectrum = uiaxes(g);
            obj.AxSpectrum.Layout.Row = 1;
            obj.AxSpectrum.Layout.Column = 2;
            title(obj.AxSpectrum, 'Spectral Response');
            xlabel(obj.AxSpectrum, 'Frequency (Hz)');
            ylabel(obj.AxSpectrum, 'Power/Frequency');
            set(obj.AxSpectrum, 'XScale', 'log', 'YScale', 'log');
            grid(obj.AxSpectrum, 'on');

            obj.AxTransfer = uiaxes(g);
            obj.AxTransfer.Layout.Row = 2;
            obj.AxTransfer.Layout.Column = [1 2];
            title(obj.AxTransfer, 'Calibration Transfer Curves');
            xlabel(obj.AxTransfer, 'Parameter');
            ylabel(obj.AxTransfer, 'dB SPL');
            grid(obj.AxTransfer, 'on');
        end

        function on_measure_reference_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_measure_reference_(), 'Measuring reference...');
        end

        function run_measure_reference_(obj)
            obj.Engine.calibrate_reference();
            obj.sync_controls_();
            obj.refresh_response_plots_();
            obj.set_status_('Reference measurement complete.', false);
        end

        function on_calibrate_tones_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_tones_(), 'Running tone calibration...');
        end

        function run_calibrate_tones_(obj)
            freqs = obj.parse_numeric_vector_(obj.ToneFreqsField.Value, 'tone frequencies');
            if isempty(freqs)
                obj.Engine.calibrate_tones();
            else
                obj.Engine.calibrate_tones(freqs);
            end
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Tone calibration complete.', false);
        end

        function on_calibrate_clicks_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_clicks_(), 'Running click calibration...');
        end

        function run_calibrate_clicks_(obj)
            durs = obj.parse_numeric_vector_(obj.ClickDurationsField.Value, 'click durations');
            if isempty(durs)
                obj.Engine.calibrate_clicks();
            else
                obj.Engine.calibrate_clicks(durs);
            end
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Click calibration complete.', false);
        end

        function on_design_filter_(obj)
            obj.with_busy_state_(@() obj.run_design_filter_(), 'Designing filter...');
        end

        function run_design_filter_(obj)
            obj.Engine.design_filter();
            obj.set_status_('Equalization filter designed.', false);
        end

        function on_save_(obj)
            obj.with_busy_state_(@() obj.run_save_(), 'Saving calibration file...');
        end

        function run_save_(obj)
            obj.Engine.save();
            obj.set_status_('Calibration saved.', false);
        end

        function on_load_(obj)
            obj.with_busy_state_(@() obj.run_load_(), 'Loading calibration file...');
        end

        function run_load_(obj)
            prevAdapter = obj.Engine.Adapter;
            eng = stimgen.calibration.Engine.load();
            if isempty(eng)
                obj.set_status_('Load cancelled.', false);
                return
            end
            if ~isempty(prevAdapter)
                eng.Adapter = prevAdapter;
            end
            obj.Engine = eng;
            obj.sync_controls_();
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Calibration loaded.', false);
        end

        function ok = apply_controls_to_engine_(obj)
            ok = false;
            try
                obj.Engine.set_configuration( ...
                    ReferenceLevel=obj.RefLevelField.Value, ...
                    ReferenceFrequency=obj.RefFreqField.Value, ...
                    MicSensitivity=obj.MicSensField.Value, ...
                    NormativeValue=obj.NormativeField.Value, ...
                    ExcitationVoltage=obj.ExcitationField.Value, ...
                    ShowLivePlots=obj.ShowLivePlotsCheck.Value);
                ok = true;
            catch ME
                obj.set_status_(sprintf('Parameter update failed: %s', ME.message), true);
                uialert(obj.Figure, ME.message, 'Parameter Error', Icon='error');
            end
        end

        function sync_controls_(obj)
            obj.RefLevelField.Value = obj.Engine.ReferenceLevel;
            obj.RefFreqField.Value = obj.Engine.ReferenceFrequency;
            obj.MicSensField.Value = obj.Engine.MicSensitivity;
            obj.NormativeField.Value = obj.Engine.NormativeValue;
            obj.ExcitationField.Value = obj.Engine.ExcitationVoltage;
            obj.ShowLivePlotsCheck.Value = obj.Engine.ShowLivePlots;
        end

        function refresh_all_plots_(obj)
            obj.refresh_response_plots_();
            obj.refresh_transfer_plot_();
        end

        function refresh_response_plots_(obj)
            cla(obj.AxTime);
            cla(obj.AxSpectrum);

            y = obj.Engine.ResponseSignal;
            fs = obj.Engine.Fs;
            if isempty(y) || fs <= 0
                title(obj.AxTime, 'Temporal Response (no data)');
                title(obj.AxSpectrum, 'Spectral Response (no data)');
                return
            end

            t = (0:numel(y)-1) ./ fs;
            plot(obj.AxTime, t, y, 'b-');
            grid(obj.AxTime, 'on');
            xlabel(obj.AxTime, 'Time (s)');
            ylabel(obj.AxTime, 'V');
            title(obj.AxTime, sprintf('Temporal Response (N=%d)', numel(y)));

            n = numel(y);
            w = flattopwin(n);
            [pxx, f] = periodogram(y, w, 2^nextpow2(n), fs, 'power');
            pxx = max(pxx, eps);
            plot(obj.AxSpectrum, f, pxx, 'r-');
            set(obj.AxSpectrum, 'XScale', 'log', 'YScale', 'log');
            grid(obj.AxSpectrum, 'on');
            xlabel(obj.AxSpectrum, 'Frequency (Hz)');
            ylabel(obj.AxSpectrum, 'Power/Frequency');
            title(obj.AxSpectrum, 'Spectral Response (periodogram)');
        end

        function refresh_transfer_plot_(obj)
            cla(obj.AxTransfer);
            grid(obj.AxTransfer, 'on');
            hold(obj.AxTransfer, 'on');

            hasData = false;
            if obj.Engine.IsCalibrated
                C = obj.Engine.CalibrationData;

                if isfield(C, 'tone') && ~isempty(C.tone)
                    semilogx(obj.AxTransfer, C.tone.frequency, C.tone.spl_db, 'o-b', ...
                        DisplayName='Tone SPL');
                    hasData = true;
                end

                if isfield(C, 'click') && ~isempty(C.click)
                    plot(obj.AxTransfer, C.click.duration * 1e6, C.click.spl_db, 's-r', ...
                        DisplayName='Click SPL');
                    hasData = true;
                end
            end

            if hasData
                xlabel(obj.AxTransfer, 'Tone: Frequency (Hz) / Click: Duration (\mus)');
                ylabel(obj.AxTransfer, 'Measured Level (dB SPL)');
                title(obj.AxTransfer, 'Calibration Transfer Curves');
                legend(obj.AxTransfer, 'Location', 'best');
            else
                title(obj.AxTransfer, 'Calibration Transfer Curves (no data)');
                xlabel(obj.AxTransfer, 'Parameter');
                ylabel(obj.AxTransfer, 'dB SPL');
            end
            hold(obj.AxTransfer, 'off');
        end

        function update_runtime_state_(obj)
            hasAdapter = ~isempty(obj.Engine.Adapter);
            if hasAdapter
                obj.BtnReference.Enable = 'on';
                obj.BtnTones.Enable = 'on';
                obj.BtnClicks.Enable = 'on';
            else
                obj.BtnReference.Enable = 'off';
                obj.BtnTones.Enable = 'off';
                obj.BtnClicks.Enable = 'off';
            end

            if obj.Engine.IsCalibrated
                obj.BtnSave.Enable = 'on';
            else
                obj.BtnSave.Enable = 'off';
            end

            if obj.Engine.IsCalibrated && isfield(obj.Engine.CalibrationData, 'tone')
                obj.BtnFilter.Enable = 'on';
            else
                obj.BtnFilter.Enable = 'off';
            end
        end

        function values = parse_numeric_vector_(~, textValue, label)
            values = [];
            if ischar(textValue)
                raw = string(textValue);
            elseif isstring(textValue)
                raw = strjoin(textValue, ' ');
            elseif iscell(textValue)
                raw = strjoin(string(textValue), ' ');
            else
                raw = "";
            end

            raw = strtrim(raw);
            if raw == "" || startsWith(raw, "(empty", IgnoreCase=true)
                return
            end

            tokens = regexp(raw, '[,;\s]+', 'split');
            tokens = tokens(~cellfun('isempty', tokens));
            vals = str2double(tokens);
            if any(isnan(vals)) || isempty(vals)
                error('stimgen:calibration:CalibrationGui:badVector', ...
                    'Could not parse %s. Use comma/space separated numbers.', label);
            end
            values = vals(:)';
            if any(values <= 0)
                error('stimgen:calibration:CalibrationGui:badVector', ...
                    '%s must contain only positive values.', label);
            end
        end

        function with_busy_state_(obj, fcn, busyMessage)
            obj.set_status_(busyMessage, false);
            obj.Figure.Pointer = 'watch';
            drawnow;
            try
                fcn();
            catch ME
                obj.set_status_(ME.message, true);
                uialert(obj.Figure, ME.message, 'Calibration Error', Icon='error');
            end
            obj.Figure.Pointer = 'arrow';
            obj.update_runtime_state_();
            drawnow;
        end

        function set_status_(obj, msg, isError)
            if isError
                obj.StatusLabel.FontColor = [0.7 0 0];
            else
                obj.StatusLabel.FontColor = [0 0 0];
            end
            obj.StatusLabel.Text = msg;
        end
    end
end
