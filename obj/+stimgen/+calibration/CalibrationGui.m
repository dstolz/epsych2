classdef CalibrationGui < handle
    % gui = stimgen.calibration.CalibrationGui()
    % gui = stimgen.calibration.CalibrationGui(eng)
    % Interactive GUI for the stimgen.calibration package.
    %
    % Provides user parameterization of calibration settings, live inspection of
    % the latest response waveform/spectrum, transfer-curve visualization for
    % tone and click calibration tables, and save/load support for .esgc files.
    % When no engine is supplied, an offline Engine is created automatically;
    % hardware can be attached later via File > Initialize Runtime From Protocol.
    %
    % Parameters:
    %   eng  - (optional) stimgen.calibration.Engine with an adapter already
    %          attached. Omit to start in offline mode.
    %   host - (optional) stimgen.HardwareHost. Required only for the runtime
    %          menu actions; omit when supplying an engine that already has an
    %          adapter, or when working offline.
    %
    % Returns:
    %   gui - GUI controller handle.
    %
    % Example:
    %   % Offline mode — load a saved calibration, no hardware:
    %   gui = stimgen.calibration.CalibrationGui();
    %
    %   % Pre-built engine with adapter:
    %   eng = stimgen.calibration.Engine(adapter);
    %   gui = stimgen.calibration.CalibrationGui(eng);
    %
    %   % Host-driven: attach hardware from the GUI menu.
    %   gui = stimgen.calibration.CalibrationGui(stimgen.calibration.Engine(), host);
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.HwAdapter,
    %           stimgen.HardwareHost,
    %           documentation/stimgen/stimgen_CalibrationGui.md,
    %           documentation/stimgen/stimgen_calibration.md

    properties (SetAccess = private)
        Engine stimgen.calibration.Engine
    end

    properties (Access = private)
        Figure
        Grid
        Host                    % stimgen.HardwareHost | []

        % Controls
        RefLevelField
        RefFreqField
        MicSensField
        NormativeField
        ExcitationField
        ShowLivePlotsCheck
        StatusLabel

        % Buttons
        BtnReference
        BtnTones
        BtnClicks
        BtnSweptSine
        BtnFilter

        % Axes
        AxTime
        AxSpectrum
        AxTransfer
    end

    methods
        function obj = CalibrationGui(eng, host)
            % obj = stimgen.calibration.CalibrationGui()
            % obj = stimgen.calibration.CalibrationGui(eng)
            % obj = stimgen.calibration.CalibrationGui(eng, host)
            % Construct and display the calibration GUI.
            %
            % Parameters:
            %   eng  - (optional) stimgen.calibration.Engine; omit for offline mode.
            %   host - (optional) stimgen.HardwareHost enabling the runtime menu
            %          actions (Initialize Runtime From Protocol, Attach Adapter).
            arguments
                eng  (1,1) stimgen.calibration.Engine = stimgen.calibration.Engine()
                host = []
            end

            if ~isempty(host)
                mustBeA(host, 'stimgen.HardwareHost');
            end

            obj.Engine = eng;
            obj.Host   = host;

            obj.build_ui_();
            obj.sync_controls_();
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.show_startup_hint_();
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

            obj.build_menu_();
            obj.build_controls_panel_();
            obj.build_plots_panel_();
        end

        function build_menu_(obj)
            % Create File menu with Load and Save options.
            fileMenu = uimenu(obj.Figure, Text='File');
            uimenu(fileMenu, Text='Initialize Runtime From Protocol...', ...
                MenuSelectedFcn=@(~,~) obj.on_initialize_runtime_());
            uimenu(fileMenu, Text='Attach Adapter', ...
                MenuSelectedFcn=@(~,~) obj.on_attach_adapter_());
            uimenu(fileMenu, Text='Disconnect Runtime/Adapter', ...
                MenuSelectedFcn=@(~,~) obj.on_disconnect_runtime_());
            uimenu(fileMenu, Text='Load .esgc', ...
                Separator='on', ...
                MenuSelectedFcn=@(~,~) obj.on_load_());
            uimenu(fileMenu, Text='Save .esgc', ...
                MenuSelectedFcn=@(~,~) obj.on_save_());

            helpMenu = uimenu(obj.Figure, Text='Help');
            uimenu(helpMenu, Text='Calibration Quick Start', ...
                MenuSelectedFcn=@(~,~) obj.on_show_quick_start_());
        end

        function build_controls_panel_(obj)
            panel = uipanel(obj.Grid, Title='Controls');
            panel.Layout.Row = 1;
            panel.Layout.Column = 1;

            g = uigridlayout(panel, [14 2]);
            g.RowHeight = {24, 24, 24, 24, 24, 24, 16, 32, 32, 32, 32, 32, 24, '1x'};
            g.ColumnWidth = {'1x', '1x'};
            g.Scrollable = 'on';

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

            obj.BtnReference = uibutton(g, Text='Measure Reference', ...
                ButtonPushedFcn=@(~,~) obj.on_measure_reference_());
            obj.BtnReference.Layout.Row = 8;
            obj.BtnReference.Layout.Column = [1 2];
            obj.BtnReference.Tooltip = 'Step 1: Measure reference tone to update microphone sensitivity.';

            obj.BtnTones = uibutton(g, Text='Calibrate Tones', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_tones_());
            obj.BtnTones.Layout.Row = 9;
            obj.BtnTones.Layout.Column = [1 2];
            obj.BtnTones.Tooltip = 'Step 2: Run tone frequency sweep to build tone calibration table.';

            obj.BtnClicks = uibutton(g, Text='Calibrate Clicks', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_clicks_());
            obj.BtnClicks.Layout.Row = 10;
            obj.BtnClicks.Layout.Column = [1 2];
            obj.BtnClicks.Tooltip = 'Optional: Build click-duration calibration table.';

            obj.BtnSweptSine = uibutton(g, Text='Calibrate Swept Sine', ...
                ButtonPushedFcn=@(~,~) obj.on_calibrate_swept_sine_());
            obj.BtnSweptSine.Layout.Row = 11;
            obj.BtnSweptSine.Layout.Column = [1 2];
            obj.BtnSweptSine.Tooltip = 'Optional: Broadband calibration with a swept-sine chirp.';

            obj.BtnFilter = uibutton(g, Text='Design Filter', ...
                ButtonPushedFcn=@(~,~) obj.on_design_filter_());
            obj.BtnFilter.Layout.Row = 12;
            obj.BtnFilter.Layout.Column = [1 2];
            obj.BtnFilter.Tooltip = 'Step 3 (optional): Design equalization filter after tone calibration.';

            obj.StatusLabel = uilabel(g, Text='Ready.', HorizontalAlignment='left');
            obj.StatusLabel.Layout.Row = 13;
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
            [freqs, repeatCount, wasCancelled] = obj.prompt_vector_parameter_( ...
                'toneFreqs', ...
                'toneRepeats', ...
                'Tone frequencies (Hz). Leave empty to use default log sweep.', ...
                'Tone Calibration', ...
                '', ...
                1);
            if wasCancelled
                obj.set_status_('Tone calibration cancelled.', false);
                return
            end
            if isempty(freqs)
                obj.Engine.calibrate_tones([], repeatCount);
            else
                obj.Engine.calibrate_tones(freqs, repeatCount);
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
            [durs, repeatCount, wasCancelled] = obj.prompt_vector_parameter_( ...
                'clickDurations', ...
                'clickRepeats', ...
                'Click durations (s). Leave empty to use default 1..128 samples.', ...
                'Click Calibration', ...
                '', ...
                1);
            if wasCancelled
                obj.set_status_('Click calibration cancelled.', false);
                return
            end
            if isempty(durs)
                obj.Engine.calibrate_clicks([], repeatCount);
            else
                obj.Engine.calibrate_clicks(durs, repeatCount);
            end
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Click calibration complete.', false);
        end

        function on_calibrate_swept_sine_(obj)
            if ~obj.apply_controls_to_engine_()
                return
            end
            obj.with_busy_state_(@() obj.run_calibrate_swept_sine_(), 'Running swept sine calibration...');
        end

        function run_calibrate_swept_sine_(obj)
            [duration, freqs, repeatCount, wasCancelled] = obj.prompt_swept_sine_parameters_();
            if wasCancelled
                obj.set_status_('Swept sine calibration cancelled.', false);
                return
            end
            if isempty(freqs)
                obj.Engine.calibrate_swept_sine(duration, [], repeatCount);
            else
                obj.Engine.calibrate_swept_sine(duration, freqs, repeatCount);
            end
            obj.refresh_all_plots_();
            obj.update_runtime_state_();
            obj.set_status_('Swept sine calibration complete.', false);
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

        function on_attach_adapter_(obj)
            obj.with_busy_state_(@() obj.run_attach_adapter_(), 'Attaching adapter...');
        end

        function run_attach_adapter_(obj)
            obj.assert_host_();
            obj.set_adapter(obj.Host.calibrationAdapter());
        end

        function on_initialize_runtime_(obj)
            obj.with_busy_state_(@() obj.run_initialize_runtime_(), 'Initializing calibration runtime...');
        end

        function run_initialize_runtime_(obj)
            obj.assert_host_();
            [fn, pn] = uigetfile( ...
                {'*.eprot;*.prot;*.json', 'Protocol files (*.eprot, *.prot, *.json)'}, ...
                'Load Protocol For Calibration');
            if isequal(fn, 0)
                obj.set_status_('Runtime initialization cancelled.', false);
                return
            end

            protocolPath = fullfile(pn, fn);

            obj.Host.loadProtocol(protocolPath);
            obj.Host.connect();
            obj.Host.setMode("Preview");

            obj.set_adapter(obj.Host.calibrationAdapter());
            obj.set_status_(sprintf('Runtime initialized from protocol: %s', fn), false);
        end

        function on_disconnect_runtime_(obj)
            obj.with_busy_state_(@() obj.run_disconnect_runtime_(), 'Disconnecting calibration runtime...');
        end

        function run_disconnect_runtime_(obj)
            if ~isempty(obj.Host) && obj.Host.connectionState() ~= "None"
                try
                    obj.Host.setMode("Idle");
                catch ME
                    stimgen.util.vprintf(0, 1, 'CalibrationGui: failed to return runtime interfaces to Idle.');
                    stimgen.util.vprintf(0, 1, ME);
                end
                obj.Host.release();
            end

            obj.Engine.Adapter = [];
            obj.update_runtime_state_();
            obj.set_status_('Calibration runtime disconnected.', false);
        end

        function assert_host_(obj)
            % Guard the hardware-backed menu actions; offline mode has no host.
            if isempty(obj.Host)
                error('stimgen:calibration:CalibrationGui:noHost', ...
                    ['No hardware host is attached. Construct CalibrationGui with a ' ...
                    'stimgen.HardwareHost, or supply an Engine that already has an adapter.']);
            end
        end

        function on_show_quick_start_(obj)
            % Show a concise calibration workflow for first-time users.
            msg = sprintf([ ...
                'Calibration Quick Start\n\n', ...
                '1) File > Initialize Runtime From Protocol..., then File > Attach Adapter (if needed).\n\n', ...
                '2) Verify parameters (reference level/frequency, mic sensitivity, excitation).\n\n', ...
                '3) Click "Measure Reference" to update microphone sensitivity.\n\n', ...
                '4) Click "Calibrate Tones" (required for tone lookup and filter design).\n\n', ...
                '5) Optional: run "Calibrate Clicks" and/or "Calibrate Swept Sine".\n\n', ...
                '6) Optional: click "Design Filter" (enabled after tone calibration).\n\n', ...
                '7) Save calibration with File > Save .esgc.']);
            uialert(obj.Figure, msg, 'Calibration Quick Start', Icon='info');
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

                if isfield(C, 'swept_sine') && ~isempty(C.swept_sine)
                    semilogx(obj.AxTransfer, C.swept_sine.frequency, C.swept_sine.spl_db, '^-g', ...
                        DisplayName='Swept Sine SPL');
                    hasData = true;
                end
            end

            if hasData
                xlabel(obj.AxTransfer, 'Frequency (Hz) / Duration (\mus)');
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
                obj.BtnSweptSine.Enable = 'on';
            else
                obj.BtnReference.Enable = 'off';
                obj.BtnTones.Enable = 'off';
                obj.BtnClicks.Enable = 'off';
                obj.BtnSweptSine.Enable = 'off';
            end

            if obj.Engine.IsCalibrated && isfield(obj.Engine.CalibrationData, 'tone')
                obj.BtnFilter.Enable = 'on';
            else
                obj.BtnFilter.Enable = 'off';
            end
        end

        function show_startup_hint_(obj)
            % Provide immediate guidance on the next actionable step.
            if isempty(obj.Engine.Adapter)
                obj.set_status_('No adapter attached. Initialize Runtime From Protocol, then Attach Adapter.', true);
                return
            end

            if obj.Engine.IsCalibrated
                obj.set_status_('Calibration loaded. Review plots or save updates.', false);
            else
                obj.set_status_('Ready. Start with "Measure Reference", then "Calibrate Tones".', false);
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

        function [values, repeatCount, wasCancelled] = prompt_vector_parameter_(obj, prefName, repeatPrefName, promptText, dlgTitle, defaultValue, repeatDefault)
            wasCancelled = false;
            stored = obj.get_pref_(prefName, defaultValue);
            repeatStored = obj.get_pref_(repeatPrefName, num2str(repeatDefault));

            prompts = {
                promptText, ...
                'Number of averages (positive integer):'
            };
            defaults = {stored, repeatStored};
            answer = inputdlg(prompts, dlgTitle, [1 90; 1 90], defaults);
            if isempty(answer)
                values = [];
                repeatCount = repeatDefault;
                wasCancelled = true;
                return
            end

            raw = strtrim(string(answer{1}));
            repeatRaw = strtrim(string(answer{2}));
            obj.set_pref_(prefName, char(raw));
            obj.set_pref_(repeatPrefName, char(repeatRaw));
            values = obj.parse_numeric_vector_(raw, lower(dlgTitle));
            repeatCount = obj.parse_positive_integer_(repeatRaw, 'number of averages');
        end

        function [duration, freqs, repeatCount, wasCancelled] = prompt_swept_sine_parameters_(obj)
            durationPref = obj.get_pref_('sweptSineDuration', '1.0');
            freqsPref = obj.get_pref_('sweptSineFreqs', '');
            repeatsPref = obj.get_pref_('sweptSineRepeats', '4');

            prompts = {
                'Swept sine duration (s, >0):', ...
                'Swept sine frequencies (Hz). Leave empty to use default log sweep:', ...
                'Number of averages (positive integer):'
            };
            defaults = {durationPref, freqsPref, repeatsPref};
            answer = inputdlg(prompts, 'Swept Sine Calibration', [1 90; 1 90; 1 90], defaults);

            if isempty(answer)
                duration = 1;
                freqs = [];
                repeatCount = 4;
                wasCancelled = true;
                return
            end

            durationText = strtrim(string(answer{1}));
            duration = str2double(durationText);
            if isnan(duration) || ~isfinite(duration) || duration <= 0
                error('stimgen:calibration:CalibrationGui:badDuration', ...
                    'Swept sine duration must be a positive number.');
            end

            freqsText = strtrim(string(answer{2}));
            freqs = obj.parse_numeric_vector_(freqsText, 'swept sine frequencies');

            repeatsText = strtrim(string(answer{3}));
            repeatCount = obj.parse_positive_integer_(repeatsText, 'number of averages');

            obj.set_pref_('sweptSineDuration', char(durationText));
            obj.set_pref_('sweptSineFreqs', char(freqsText));
            obj.set_pref_('sweptSineRepeats', char(repeatsText));
            wasCancelled = false;
        end

        function value = parse_positive_integer_(~, textValue, label)
            raw = strtrim(string(textValue));
            value = str2double(raw);
            if isnan(value) || ~isfinite(value) || value <= 0 || value ~= round(value)
                error('stimgen:calibration:CalibrationGui:badInteger', ...
                    '%s must be a positive integer.', label);
            end
            value = round(value);
        end

        function value = get_pref_(~, prefName, defaultValue)
            groupName = 'StimCalibrationGui';
            if ispref(groupName, prefName)
                value = getpref(groupName, prefName);
            else
                value = defaultValue;
            end
            value = char(string(value));
        end

        function set_pref_(~, prefName, value)
            groupName = 'StimCalibrationGui';
            setpref(groupName, prefName, char(string(value)));
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
