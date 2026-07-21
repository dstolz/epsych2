classdef Engine < handle
    % stimgen.calibration.Engine
    % Core calibration engine: SPL-to-voltage lookup table generator.
    %
    % Orchestrates reference measurement, tone and click sweeps, and provides
    % compute_adjusted_voltage() for real-time stimulus scaling. An optional
    % equalization filter can be designed as a post-calibration step.
    %
    % Uses a unified SPL/voltage model for both tones and clicks: peak
    % measurements are converted to RMS equivalent before computing dB SPL.
    % All calibration runs are atomic - a failure aborts the run and no
    % partial data is retained.
    %
    % CalibrationData is empty ([]) until a successful run completes.
    % After a successful run it is a struct with fields:
    %   tone             - struct: frequency, measurement, spl_db, voltage (Nx1); metrics sub-struct
    %   click            - struct: duration, measurement, spl_db, voltage (Nx1); metrics sub-struct
    %   swept_sine       - struct: frequency, measurement, spl_db, voltage (Nx1); metrics sub-struct
    %   filter           - digitalFilter | [] (populated by design_filter)
    %   filterGrpDelay   - int (group delay samples; 0 until design_filter runs)
    %
    % Usage:
    %   adapter = stimgen.calibration.WindowsSoundCardAdapter();
    %   eng = stimgen.calibration.Engine(adapter);
    %   eng.ReferenceFrequency = 1000;
    %   eng.calibrate_reference();
    %   eng.calibrate_tones([], 3);     % 3 averages per frequency
    %   eng.calibrate_clicks([], 3);
    %   eng.design_filter();            % optional
    %   eng.save('my_cal.esgc');
    %
    %   % offline use (no adapter needed):
    %   eng = stimgen.calibration.Engine.load('my_cal.esgc');
    %   v   = eng.compute_adjusted_voltage("tone", 4000, 70);
    %
    % See also: stimgen.calibration.HwAdapter,
    %           stimgen.calibration.WindowsSoundCardAdapter,
    %           documentation/stimgen/stimgen_calibration.md

    % --- Persistent calibration parameters ---
    properties (SetAccess = protected, SetObservable, AbortSet)
        MicSensitivity      (1,1) double {mustBePositive,mustBeFinite}      = 1     % V/Pa
        ReferenceLevel      (1,1) double {mustBePositive,mustBeFinite}      = 94    % dB SPL
        ReferenceFrequency  (1,1) double {mustBePositive,mustBeFinite}      = 1000  % Hz
        NormativeValue      (1,1) double {mustBePositive,mustBeFinite}      = 80    % dB SPL
        ExcitationVoltage   (1,1) double {mustBePositive}                   = 1     % V (<=10)
        ShowLivePlots       (1,1) logical                                   = false
        CalibrationTimestamp (1,1) datetime = datetime("")
    end

    % --- Calibration results and transient signals ---
    properties (SetAccess = protected)
        CalibrationData = []    % struct (see class doc) or [] if uncalibrated
        Adapter                 % stimgen.calibration.HwAdapter | []
        ExcitationSignal (1,:) double = []
        ResponseSignal   (1,:) double = []
        ResponseTHD      (1,1) double = nan
    end

    properties (Dependent)
        Fs          % sample rate from adapter (0 if no adapter)
        IsCalibrated % true when CalibrationData is a non-empty struct
    end

    methods
        function obj = Engine(adapter)
            % obj = stimgen.calibration.Engine()
            % obj = stimgen.calibration.Engine(adapter)
            %
            % Construct a calibration engine. Supply an HwAdapter to enable
            % live measurement; omit it for offline compute_adjusted_voltage
            % use only.
            %
            % Parameters:
            %   adapter - stimgen.calibration.HwAdapter | [] (default [])
            arguments
                adapter = []
            end
            if ~isempty(adapter)
                if ~isa(adapter, 'stimgen.calibration.HwAdapter')
                    error('stimgen:calibration:Engine:badAdapter', ...
                        'adapter must be a stimgen.calibration.HwAdapter.');
                end
            end
            obj.Adapter = adapter;
        end

        set_configuration(obj, options) % Update engine calibration parameters.
        calibrate_reference(obj) % Measure microphone sensitivity from reference tone.
        calibrate_tones(obj, freqs, repeatCount) % Build tone calibration LUT.
        calibrate_clicks(obj, durs, repeatCount) % Build click calibration LUT.
        calibrate_swept_sine(obj, duration, freqs, repeatCount) % Run swept-sine calibration.
        design_filter(obj) % Design equalization filter from tone LUT.
        v = compute_adjusted_voltage(obj, type, value, level) % Interpolate LUT voltage.
        save(obj, ffn) % Save calibration to .esgc file.

        function Fs = get.Fs(obj)
            % Return adapter sample rate or 0 when no adapter is attached.
            if isempty(obj.Adapter)
                Fs = 0;
            else
                Fs = obj.Adapter.sample_rate();
            end
        end

        function tf = get.IsCalibrated(obj)
            % True when CalibrationData is a non-empty struct.
            tf = isstruct(obj.CalibrationData) && ~isempty(obj.CalibrationData);
        end

        function plot_reset(obj)
            % Clear calibration plot axes.
            obj.plot_signal(true);
            obj.plot_spectrum(true);
            obj.plot_transfer('', [], true);
            drawnow;
        end

        plot_signal(obj, reset) % Plot current response waveform.
        plot_spectrum(obj, reset) % Plot current response spectrum.
        plot_transfer(obj, type, tableData, reset) % Plot transfer data overlays.
    end

    methods (Access = private)
        function assert_adapter_(obj)
            % Raise an error when no hardware adapter is attached.
            if isempty(obj.Adapter)
                error('stimgen:calibration:Engine:noAdapter', ...
                    'No HwAdapter attached. Provide an adapter to run calibrations.');
            end
        end

        r = measure_(obj, signal, mode, options) % Acquire and compute measurement metric.
        [spl_db, voltage] = compute_spl_voltage_(obj, measurement, mode) % Convert measurement to SPL and normative voltage.
        [noiseFloorDb, snrDb] = estimate_noise_snr_(obj, y, fs, toneFreq) % Estimate noise floor and SNR.
        [thdDb, h2Db, h3Db] = estimate_harmonics_(obj, y, fs, fundamentalFreq) % Estimate THD and harmonic levels.
        metrics = estimate_transfer_metrics_(obj, x, y, fs) % Estimate transfer-function metrics.
        stats = repeatability_stats_(obj, values) % Summarize repeatability statistics.
        m = estimate_headroom_(obj, excitation, response) % Estimate clipping and headroom margins.
        out = aggregate_headroom_(obj, metricsArray) % Aggregate headroom metrics over repeats.
        y = trim_response_(obj, y) % Trim response padding and delay.
        cd = commit_cal_data_(obj) % Build calibration output struct.

        function t = empty_table_(~, n)
            % Allocate a calibration table struct for in-progress runs.
            t = struct('x', nan(1,n), 'measurement', nan(1,n), ...
                       'spl_db', nan(1,n), 'voltage', nan(1,n));
        end

        restore_from_struct_(obj, s) % Restore engine state from saved struct.
    end

    methods (Static)
        eng = load(ffn) % Load engine calibration from .esgc file.
        r = spectral_rms(x, freq, fs) % Estimate RMS amplitude at a frequency.
    end

    methods (Static, Access = private)
        function f = cal_fig_(name)
            % Return/create named figure used by calibration plotting helpers.
            f = findobj('Type', 'figure', 'Name', name);
            if isempty(f)
                f = figure('Name', name, 'NumberTitle', 'off');
            end
            figure(f);
        end

        function s = rmfield_safe_(s, fname)
            % Remove struct field only when present.
            if isstruct(s) && isfield(s, fname)
                s = rmfield(s, fname);
            end
        end
    end
end
