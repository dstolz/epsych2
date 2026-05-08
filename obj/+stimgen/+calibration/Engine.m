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
    % All calibration runs are atomic — a failure aborts the run and no
    % partial data is retained.
    %
    % CalibrationData is empty ([]) until a successful run completes.
    % After a successful run it is a struct with fields:
    %   tone             - struct: frequency, measurement, spl_db, voltage (Nx1)
    %   click            - struct: duration, measurement, spl_db, voltage (Nx1)
    %   filter           - digitalFilter | [] (populated by design_filter)
    %   filterGrpDelay   - int (group delay samples; 0 until design_filter runs)
    %
    % Usage:
    %   adapter = stimgen.calibration.InterfaceAdapter(RUNTIME.HW);
    %   eng = stimgen.calibration.Engine(adapter);
    %   eng.ReferenceFrequency = 1000;
    %   eng.calibrate_reference();
    %   eng.calibrate_tones();
    %   eng.calibrate_clicks();
    %   eng.design_filter();       % optional
    %   eng.save('my_cal.esgc');
    %
    %   % offline use (no adapter needed):
    %   eng = stimgen.calibration.Engine.load('my_cal.esgc');
    %   v   = eng.compute_adjusted_voltage("tone", 4000, 70);
    %
    % See also: stimgen.calibration.HwAdapter,
    %           stimgen.calibration.InterfaceAdapter,
    %           documentation/stimgen/stimgen_calibration.md

    % --- Persistent calibration parameters ---
    properties (SetAccess = protected, SetObservable, AbortSet)
        MicSensitivity      (1,1) double {mustBePositive,mustBeFinite}      = 1     % V/Pa
        ReferenceLevel      (1,1) double {mustBePositive,mustBeFinite}      = 94    % dB SPL
        ReferenceFrequency  (1,1) double {mustBePositive,mustBeFinite}      = 1000  % Hz
        NormativeValue      (1,1) double {mustBePositive,mustBeFinite}      = 80    % dB SPL
        ExcitationVoltage   (1,1) double {mustBePositive}                   = 1     % V (≤10)
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

    % ------------------------------------------------------------------ %
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

        % ---------------------------------------------------------- %
        function set_configuration(obj, options)
            % set_configuration(obj)
            % set_configuration(obj, Name=Value)
            %
            % Update engine calibration parameters in one call.
            %
            % Parameters (Name=Value):
            %   MicSensitivity     - (1,1) double, > 0
            %   ReferenceLevel     - (1,1) double, > 0
            %   ReferenceFrequency - (1,1) double, > 0
            %   NormativeValue     - (1,1) double, > 0
            %   ExcitationVoltage  - (1,1) double, > 0
            %   ShowLivePlots      - (1,1) logical
            arguments
                obj
                options.MicSensitivity     (1,1) double {mustBePositive,mustBeFinite} = obj.MicSensitivity
                options.ReferenceLevel     (1,1) double {mustBePositive,mustBeFinite} = obj.ReferenceLevel
                options.ReferenceFrequency (1,1) double {mustBePositive,mustBeFinite} = obj.ReferenceFrequency
                options.NormativeValue     (1,1) double {mustBePositive,mustBeFinite} = obj.NormativeValue
                options.ExcitationVoltage  (1,1) double {mustBePositive} = obj.ExcitationVoltage
                options.ShowLivePlots      (1,1) logical = obj.ShowLivePlots
            end

            obj.MicSensitivity    = options.MicSensitivity;
            obj.ReferenceLevel    = options.ReferenceLevel;
            obj.ReferenceFrequency = options.ReferenceFrequency;
            obj.NormativeValue    = options.NormativeValue;
            obj.ExcitationVoltage = options.ExcitationVoltage;
            obj.ShowLivePlots     = options.ShowLivePlots;
        end

        % ---------------------------------------------------------- %
        function calibrate_reference(obj)
            % calibrate_reference(obj)
            % Measure the microphone sensitivity using a 1-second tone at
            % ReferenceFrequency. Updates MicSensitivity.
            obj.assert_adapter_();
            fs = obj.Fs;

            so         = stimgen.Tone;
            so.Fs      = fs;
            so.Duration = 1;
            so.Frequency = obj.ReferenceFrequency;
            so.update_signal();

            y = obj.ExcitationVoltage .* so.Signal;
            obj.ExcitationSignal = y;

            r = obj.measure_(y, "specfreq", StimFrequency=obj.ReferenceFrequency);

            % Convert measured RMS voltage to V/Pa.
            % At ReferenceLevel dB SPL (standard 94 dB = 1 Pa),
            % dv = 1 → MicSensitivity = r V/Pa.
            dv = 10 ^ ((obj.ReferenceLevel - 94) / 20);
            obj.MicSensitivity = r / dv;

            vprintf(1, 'Mic sensitivity = %.4f V @ %.1f dB SPL = %.4f V/Pa', ...
                r, obj.ReferenceLevel, obj.MicSensitivity);
        end

        % ---------------------------------------------------------- %
        function calibrate_tones(obj, freqs, repeatCount)
            % calibrate_tones(obj)
            % calibrate_tones(obj, freqs)
            % calibrate_tones(obj, freqs, repeatCount)
            %
            % Sweep across frequencies and build the tone calibration LUT.
            % Aborts and clears any prior tone data on error.
            %
            % Parameters:
            %   freqs - (1,:) double frequency vector in Hz (default: 50-point
            %           log sweep from 100 Hz to Nyquist)
            %   repeatCount - (1,1) double positive integer number of
            %                 measurements to average per frequency
            arguments
                obj
                freqs (1,:) double = []
                repeatCount (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1
            end
            obj.assert_adapter_();
            fs = obj.Fs;

            if isempty(freqs)
                freqs = 100 .* 2.^(linspace(0, 9, 50));
                freqs(freqs > fs * 0.5) = [];
            end

            so            = stimgen.Tone;
            so.Fs         = fs;
            so.Duration   = 0.1;

            n         = numel(freqs);
            tone_data = obj.empty_table_(n);
            toneMeasAll = nan(repeatCount, n);
            toneSnrAll = nan(repeatCount, n);
            toneNoiseFloorAll = nan(repeatCount, n);
            toneThdAll = nan(repeatCount, n);
            toneH2All = nan(repeatCount, n);
            toneH3All = nan(repeatCount, n);
            toneHeadroomAll = repmat(struct( ...
                'assumedFullScaleV', nan, ...
                'excitationPeakV', nan, ...
                'excitationHeadroomDb', nan, ...
                'excitationClippingLikely', false, ...
                'responsePeakV', nan, ...
                'responseHeadroomDb', nan, ...
                'responseFlatTopFraction', nan, ...
                'responseClippingLikely', false), repeatCount, n);

            if obj.ShowLivePlots
                obj.plot_reset();
            end

            try
                for i = 1:n
                    vprintf(1, '[%d/%d] Calibrating tone %.3f kHz', i, n, freqs(i)/1000);
                    so.Frequency     = freqs(i);
                    so.WindowDuration = 4 / freqs(i);
                    so.update_signal();

                    y = obj.ExcitationVoltage .* so.Signal;
                    obj.ExcitationSignal = y;

                    m = 0;
                    for rep = 1:repeatCount
                        mRep = obj.measure_(y, "specfreq", StimFrequency=freqs(i));
                        m = m + mRep;
                        toneMeasAll(rep, i) = mRep;
                        response = obj.ResponseSignal;
                        [toneNoiseFloorAll(rep, i), toneSnrAll(rep, i)] = obj.estimate_noise_snr_(response, fs, freqs(i));
                        [toneThdAll(rep, i), toneH2All(rep, i), toneH3All(rep, i)] = obj.estimate_harmonics_(response, fs, freqs(i));
                        toneHeadroomAll(rep, i) = obj.estimate_headroom_(y, response);
                    end
                    m = m ./ repeatCount;
                    [spl, volt] = obj.compute_spl_voltage_(m, "specfreq");

                    tone_data.x(i)           = freqs(i);
                    tone_data.measurement(i) = m;
                    tone_data.spl_db(i)      = spl;
                    tone_data.voltage(i)     = volt;

                    if obj.ShowLivePlots
                        obj.plot_signal();
                        obj.plot_spectrum();
                        obj.plot_transfer('tone', tone_data);
                    end
                end
            catch ME
                % Abort: do not persist partial data.
                if isstruct(obj.CalibrationData)
                    obj.CalibrationData = stimgen.calibration.Engine.rmfield_safe_(obj.CalibrationData, 'tone');
                end
                vprintf(0, 2, 'Tone calibration aborted: %s', ME.message);
                rethrow(ME);
            end

            % Commit only on full success.
            cd_out = obj.commit_cal_data_();
            toneSensitivity = tone_data.spl_db(:) - 20*log10(max(obj.ExcitationVoltage, eps));
            toneRepeatability = obj.repeatability_stats_(toneMeasAll);
            toneHeadroom = obj.aggregate_headroom_(toneHeadroomAll(:));
            toneNoiseFloor = mean(toneNoiseFloorAll, 1, 'omitnan');
            toneSnr = mean(toneSnrAll, 1, 'omitnan');
            toneThd = mean(toneThdAll, 1, 'omitnan');
            toneH2 = mean(toneH2All, 1, 'omitnan');
            toneH3 = mean(toneH3All, 1, 'omitnan');
            cd_out.tone = struct( ...
                'frequency',   freqs(:), ...
                'measurement', tone_data.measurement(:), ...
                'spl_db',      tone_data.spl_db(:), ...
                'voltage',     tone_data.voltage(:), ...
                'metrics', struct( ...
                    'frequency_response_hz', freqs(:), ...
                    'frequency_response_db_spl', tone_data.spl_db(:), ...
                    'calibrated_level_sensitivity_db_per_v', toneSensitivity, ...
                    'noise_floor_db', toneNoiseFloor(:), ...
                    'snr_db', toneSnr(:), ...
                    'thd_db', toneThd(:), ...
                    'h2_db', toneH2(:), ...
                    'h3_db', toneH3(:), ...
                    'repeatability', toneRepeatability, ...
                    'clipping_headroom', toneHeadroom));
            obj.CalibrationData = cd_out;
            obj.CalibrationTimestamp = datetime('now');
        end

        % ---------------------------------------------------------- %
        function calibrate_clicks(obj, durs, repeatCount)
            % calibrate_clicks(obj)
            % calibrate_clicks(obj, durs)
            % calibrate_clicks(obj, durs, repeatCount)
            %
            % Sweep across click durations and build the click calibration LUT.
            % Aborts and clears any prior click data on error.
            %
            % Parameters:
            %   durs - (1,:) double click durations in seconds
            %          (default: 8-point geometric series 1..128 samples)
            %   repeatCount - (1,1) double positive integer number of
            %                 measurements to average per duration
            arguments
                obj
                durs (1,:) double = []
                repeatCount (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 1
            end
            obj.assert_adapter_();
            fs = obj.Fs;

            if isempty(durs)
                durs = 2.^(0:7) ./ fs;
            end

            so            = stimgen.ClickTrain;
            so.Fs         = fs;
            so.Duration   = 0.05;
            so.Rate       = 1;
            so.WindowFcn  = "";
            so.OnsetDelay = 0.01;

            n          = numel(durs);
            click_data = obj.empty_table_(n);
            clickMeasAll = nan(repeatCount, n);
            clickSnrAll = nan(repeatCount, n);
            clickNoiseFloorAll = nan(repeatCount, n);
            clickThdAll = nan(repeatCount, n);
            clickHeadroomAll = repmat(struct( ...
                'assumedFullScaleV', nan, ...
                'excitationPeakV', nan, ...
                'excitationHeadroomDb', nan, ...
                'excitationClippingLikely', false, ...
                'responsePeakV', nan, ...
                'responseHeadroomDb', nan, ...
                'responseFlatTopFraction', nan, ...
                'responseClippingLikely', false), repeatCount, n);

            if obj.ShowLivePlots
                obj.plot_reset();
            end

            try
                for i = 1:n
                    vprintf(1, '[%d/%d] Calibrating click %.2f μs', i, n, durs(i)*1e6);
                    so.ClickDuration = durs(i);
                    so.update_signal();

                    y = obj.ExcitationVoltage .* so.Signal;
                    obj.ExcitationSignal = y;

                    m = 0;
                    for rep = 1:repeatCount
                        mRep = obj.measure_(y, "peak");
                        m = m + mRep;
                        clickMeasAll(rep, i) = mRep;
                        response = obj.ResponseSignal;
                        [clickNoiseFloorAll(rep, i), clickSnrAll(rep, i)] = obj.estimate_noise_snr_(response, fs, nan);
                        clickThdAll(rep, i) = thd(response, fs);
                        clickHeadroomAll(rep, i) = obj.estimate_headroom_(y, response);
                    end
                    m = m ./ repeatCount;
                    [spl, volt] = obj.compute_spl_voltage_(m, "peak");

                    click_data.x(i)           = durs(i);
                    click_data.measurement(i) = m;
                    click_data.spl_db(i)      = spl;
                    click_data.voltage(i)     = volt;

                    if obj.ShowLivePlots
                        obj.plot_signal();
                        obj.plot_spectrum();
                        obj.plot_transfer('click', click_data);
                    end
                end
            catch ME
                if isstruct(obj.CalibrationData)
                    obj.CalibrationData = stimgen.calibration.Engine.rmfield_safe_(obj.CalibrationData, 'click');
                end
                vprintf(0, 2, 'Click calibration aborted: %s', ME.message);
                rethrow(ME);
            end

            cd_out = obj.commit_cal_data_();
            clickSensitivity = click_data.spl_db(:) - 20*log10(max(obj.ExcitationVoltage, eps));
            clickRepeatability = obj.repeatability_stats_(clickMeasAll);
            clickHeadroom = obj.aggregate_headroom_(clickHeadroomAll(:));
            clickNoiseFloor = mean(clickNoiseFloorAll, 1, 'omitnan');
            clickSnr = mean(clickSnrAll, 1, 'omitnan');
            clickThd = mean(clickThdAll, 1, 'omitnan');
            cd_out.click = struct( ...
                'duration',    durs(:), ...
                'measurement', click_data.measurement(:), ...
                'spl_db',      click_data.spl_db(:), ...
                'voltage',     click_data.voltage(:), ...
                'metrics', struct( ...
                    'calibrated_level_sensitivity_db_per_v', clickSensitivity, ...
                    'noise_floor_db', clickNoiseFloor(:), ...
                    'snr_db', clickSnr(:), ...
                    'thd_db', clickThd(:), ...
                    'h2_db', nan(size(clickThd(:))), ...
                    'h3_db', nan(size(clickThd(:))), ...
                    'repeatability', clickRepeatability, ...
                    'clipping_headroom', clickHeadroom));
            obj.CalibrationData = cd_out;
            obj.CalibrationTimestamp = datetime('now');
        end

        % ---------------------------------------------------------- %
        function calibrate_swept_sine(obj, duration, freqs, repeatCount)
            % calibrate_swept_sine(obj)
            % calibrate_swept_sine(obj, duration)
            % calibrate_swept_sine(obj, duration, freqs)
            % calibrate_swept_sine(obj, duration, freqs, repeatCount)
            %
            % Perform broadband calibration using a log-sine chirp sweep.
            % The chirp exponentially increases frequency from ~100 Hz to
            % Nyquist, covering the entire spectrum in one measurement. Spectral
            % analysis at discrete frequency points yields a transfer function
            % and frequency-dependent SPL calibration.
            %
            % The log-sine chirp has exceptional properties for measuring
            % frequency response: naturally pink spectrum, low crest factor (~4 dB),
            % and unique time-separation of harmonic distortion in the impulse
            % response. See Chan (2010) "Swept Sine Chirps for Measuring Impulse
            % Response" for theory and measurement validation.
            %
            % Parameters:
            %   duration - (1,1) double chirp length in seconds (default: 1)
            %   freqs    - (1,:) double frequency vector in Hz where calibration
            %              is sampled (default: 50-point log sweep from 100 Hz
            %              to Nyquist)
            %   repeatCount - (1,1) double positive integer number of
            %                 chirp captures to average (default: 4)
            arguments
                obj
                duration (1,1) double {mustBePositive,mustBeFinite} = 1
                freqs (1,:) double = []
                repeatCount (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 4
            end
            obj.assert_adapter_();
            fs = obj.Fs;
            nyquist = fs / 2;

            % Default frequency points: log-distributed from 100 Hz to Nyquist
            if isempty(freqs)
                freqs = 100 .* 2.^(linspace(0, log2(nyquist/100), 50));
                freqs(freqs > nyquist) = [];
            end

            % Ensure all frequencies are valid
            freqs = freqs(freqs > 20 & freqs < nyquist);
            if isempty(freqs)
                error('stimgen:calibration:Engine:noValidFreqs', ...
                      'No valid frequencies in range [20 Hz, %g Hz].', nyquist);
            end

            so = stimgen.SweptSine;
            so.Fs = fs;
            so.Duration = duration;
            so.StartFrequency = 100;
            so.StopFrequency = min(nyquist * 0.95, 20000);
            so.ChirpType = "log-sine";
            so.update_signal();

            y = obj.ExcitationVoltage .* so.Signal;
            obj.ExcitationSignal = y;

            n = numel(freqs);
            swept_sine_data = obj.empty_table_(n);
            measAll = nan(repeatCount, n);
            thdAll = nan(repeatCount, 1);
            responses = cell(repeatCount, 1);

            if obj.ShowLivePlots
                obj.plot_reset();
            end

            try
                vprintf(1, 'Analyzing swept sine response at %d frequencies (%d averages)...', n, repeatCount);
                for rep = 1:repeatCount
                    vprintf(1, '[%d/%d] Capturing swept sine response', rep, repeatCount);
                    raw = obj.Adapter.play_and_record(y);
                    response = obj.trim_response_(raw);
                    responses{rep} = response;
                    obj.ResponseSignal = response;
                    thdAll(rep) = thd(response, fs);

                    for i = 1:n
                        measAll(rep, i) = stimgen.calibration.Engine.spectral_rms(response, freqs(i), fs);
                    end

                    if obj.ShowLivePlots
                        for i = 1:n
                            mAvg = mean(measAll(1:rep, i), 'omitnan');
                            [spl, volt] = obj.compute_spl_voltage_(mAvg, "specfreq");
                            swept_sine_data.x(i) = freqs(i);
                            swept_sine_data.measurement(i) = mAvg;
                            swept_sine_data.spl_db(i) = spl;
                            swept_sine_data.voltage(i) = volt;
                        end
                        obj.plot_spectrum();
                        obj.plot_transfer('swept_sine', swept_sine_data);
                    end
                end

                minLen = min(cellfun(@numel, responses));
                stacked = zeros(repeatCount, minLen);
                for rep = 1:repeatCount
                    stacked(rep, :) = responses{rep}(1:minLen);
                end
                obj.ResponseSignal = mean(stacked, 1);
                obj.ResponseTHD = mean(thdAll, 'omitnan');

                for i = 1:n
                    m = mean(measAll(:, i), 'omitnan');
                    [spl, volt] = obj.compute_spl_voltage_(m, "specfreq");
                    swept_sine_data.x(i)           = freqs(i);
                    swept_sine_data.measurement(i) = m;
                    swept_sine_data.spl_db(i)      = spl;
                    swept_sine_data.voltage(i)     = volt;
                end
            catch ME
                if isstruct(obj.CalibrationData)
                    obj.CalibrationData = stimgen.calibration.Engine.rmfield_safe_(obj.CalibrationData, 'swept_sine');
                end
                vprintf(0, 2, 'Swept sine calibration aborted: %s', ME.message);
                rethrow(ME);
            end

            % Commit only on full success
            cd_out = obj.commit_cal_data_();
            transferMetrics = obj.estimate_transfer_metrics_(y, obj.ResponseSignal, fs);
            [noiseFloorDb, snrDb] = obj.estimate_noise_snr_(obj.ResponseSignal, fs, nan);
            sweptRepeatability = obj.repeatability_stats_(measAll);
            sweptHeadroomAll = repmat(struct( ...
                'assumedFullScaleV', nan, ...
                'excitationPeakV', nan, ...
                'excitationHeadroomDb', nan, ...
                'excitationClippingLikely', false, ...
                'responsePeakV', nan, ...
                'responseHeadroomDb', nan, ...
                'responseFlatTopFraction', nan, ...
                'responseClippingLikely', false), repeatCount, 1);
            for rep = 1:repeatCount
                sweptHeadroomAll(rep) = obj.estimate_headroom_(y, responses{rep});
            end
            sweptHeadroom = obj.aggregate_headroom_(sweptHeadroomAll);
            sweptSensitivity = swept_sine_data.spl_db(:) - 20*log10(max(obj.ExcitationVoltage, eps));
            cd_out.swept_sine = struct( ...
                'frequency',   freqs(:), ...
                'measurement', swept_sine_data.measurement(:), ...
                'spl_db',      swept_sine_data.spl_db(:), ...
                'voltage',     swept_sine_data.voltage(:), ...
                'duration',    duration, ...
                'chirp_type',  "log-sine", ...
                'start_freq',  100, ...
                'stop_freq',   min(nyquist * 0.95, 20000), ...
                'metrics', struct( ...
                    'frequency_response_hz', transferMetrics.frequency_hz, ...
                    'frequency_response_db', transferMetrics.magnitude_db, ...
                    'phase_deg', transferMetrics.phase_deg, ...
                    'impulse_response', transferMetrics.impulse_response, ...
                    'group_delay_samples', transferMetrics.group_delay_samples, ...
                    'group_delay_seconds', transferMetrics.group_delay_seconds, ...
                    'calibrated_level_sensitivity_db_per_v', sweptSensitivity, ...
                    'noise_floor_db', noiseFloorDb, ...
                    'snr_db', snrDb, ...
                    'thd_db', obj.ResponseTHD, ...
                    'h2_db', nan, ...
                    'h3_db', nan, ...
                    'repeatability', sweptRepeatability, ...
                    'clipping_headroom', sweptHeadroom));
            obj.CalibrationData = cd_out;
            obj.CalibrationTimestamp = datetime('now');

            vprintf(1, 'Swept sine calibration complete. THD: %.2f dB', obj.ResponseTHD);
        end

        % ---------------------------------------------------------- %
        function design_filter(obj)
            % design_filter(obj)
            % Design an arbitrary-magnitude FIR equalizer from the tone LUT.
            % Stores the result in CalibrationData.filter and
            % CalibrationData.filterGrpDelay.
            % Requires a completed tone calibration.
            if ~obj.IsCalibrated || ~isfield(obj.CalibrationData, 'tone')
                error('stimgen:calibration:Engine:noToneData', ...
                    'Tone calibration must be completed before designing the filter.');
            end
            vprintf(1, 'Designing equalization filter...');

            fs   = obj.Fs;
            d    = obj.CalibrationData.tone;
            freq = d.frequency;
            volt = d.voltage;

            % Build [0, freqs, Nyquist] amplitude table.
            fAll = [0;      freq(:); fs/2];
            aAll = [volt(1); volt(:); volt(end)];

            % Normalize to [0 1] range for designfilt; clamp endpoint.
            fn       = fAll ./ (fs / 2);
            fn(end)  = 1;
            nOrd     = length(freq);

            filt = designfilt('arbmagfir', ...
                'FilterOrder',  nOrd, ...
                'Frequencies',  fn, ...
                'Amplitudes',   aAll, ...
                'SampleRate',   fs);

            gd = round(mean(grpdelay(filt)));

            obj.CalibrationData.filter       = filt;
            obj.CalibrationData.filterGrpDelay = gd;

            vprintf(1, 'Filter designed: order=%d, group delay=%d samples', nOrd, gd);
            fprintf('<a href="matlab:fvtool(ans)">View filter</a>\n');
            assignin('base', 'ans', filt);
        end

        % ---------------------------------------------------------- %
        function v = compute_adjusted_voltage(obj, type, value, level)
            % v = compute_adjusted_voltage(obj, type, value, level)
            % Interpolate the calibration LUT and scale to the requested level.
            %
            % Parameters:
            %   type  - "tone" | "click" | "swept_sine" | "filter" | "noise"
            %   value - frequency (Hz) for "tone", "swept_sine", "filter", "noise";
            %           duration (s) for "click". For "filter"/"noise", if value
            %           is NaN/non-positive, ReferenceFrequency is used.
            %   level - target sound level in dB SPL
            %
            % Returns:
            %   v - required output voltage (double)
            if ~obj.IsCalibrated
                error('stimgen:calibration:Engine:notCalibrated', ...
                    'No calibration data available. Run calibration or load a .esgc file.');
            end

            type = lower(string(type));
            if type == "noise"
                % Legacy alias used by older stimulus classes.
                type = "filter";
            end

            if type == "filter"
                % Filter/noise playback is anchored to the tone LUT.
                lutType = "tone";
                if ~isfinite(value) || value <= 0
                    value = obj.ReferenceFrequency;
                end
            else
                lutType = type;
            end

            if ~isfield(obj.CalibrationData, lutType) || isempty(obj.CalibrationData.(lutType))
                error('stimgen:calibration:Engine:missingTypeCalibration', ...
                    'Calibration data for type "%s" is not available.', lutType);
            end

            d = obj.CalibrationData.(lutType);
            if lutType == "swept_sine" || lutType == "tone"
                x = d.frequency;
            else
                x = d.duration;
            end
            z = d.voltage;

            n = makima(x, z, value);  % normative voltage at requested parameter
            v = n .* 10 .^ ((level - obj.NormativeValue) ./ 20);

        end

        % ---------------------------------------------------------- %
        function save(obj, ffn)
            % obj.save()
            % obj.save(ffn)
            % Save calibration to a .esgc file.
            %
            % Parameters:
            %   ffn - full file path (char, optional); prompts if omitted
            arguments
                obj
                ffn (1,:) char = ''
            end
            if ~obj.IsCalibrated
                error('stimgen:calibration:Engine:notCalibrated', ...
                    'Nothing to save — calibration has not been run.');
            end
            if isempty(ffn)
                pn = getpref('StimCalibration', 'path', pwd);
                [fn, pn] = uiputfile( ...
                    {'*.esgc','EPsych Stim Calibration (*.esgc)'}, ...
                    'Save Calibration', pn);
                if isequal(fn, 0), return; end
                ffn = fullfile(pn, fn);
                setpref('StimCalibration', 'path', pn);
            end
            [~, ~, ext] = fileparts(ffn);
            if ~strcmpi(ext, '.esgc')
                ffn = [ffn '.esgc'];
            end

            s.version             = 1;
            s.CalibrationData     = obj.CalibrationData;
            s.MicSensitivity      = obj.MicSensitivity;
            s.NormativeValue      = obj.NormativeValue;
            s.ReferenceLevel      = obj.ReferenceLevel;
            s.ReferenceFrequency  = obj.ReferenceFrequency;
            s.ExcitationVoltage   = obj.ExcitationVoltage;
            s.CalibrationTimestamp = obj.CalibrationTimestamp;

            save(ffn, '-struct', 's');
            vprintf(0, 'Saved calibration: "%s"', ffn);
        end

        % ---------------------------------------------------------- %
        % Dependent property accessors

        function Fs = get.Fs(obj)
            if isempty(obj.Adapter)
                Fs = 0;
            else
                Fs = obj.Adapter.sample_rate();
            end
        end

        function tf = get.IsCalibrated(obj)
            tf = isstruct(obj.CalibrationData) && ~isempty(obj.CalibrationData);
        end

        % ---------------------------------------------------------- %
        % Plotting helpers

        function plot_reset(obj)
            % plot_reset(obj)
            % Clear calibration plot axes.
            obj.plot_signal(true);
            obj.plot_spectrum(true);
            obj.plot_transfer('', [], true);
            drawnow;
        end

        function plot_signal(obj, reset)
            % plot_signal(obj)  — plot current ResponseSignal vs time
            % plot_signal(obj, true) — clear axes
            arguments
                obj
                reset (1,1) logical = false
            end
            f = stimgen.calibration.Engine.cal_fig_('signal');
            ax = subplot(2,1,1, 'Parent', f);
            if reset, cla(ax); drawnow; return; end
            if isempty(obj.ResponseSignal), return; end
            fs = obj.Fs;
            if fs == 0, return; end
            t = (0:numel(obj.ResponseSignal)-1) ./ fs;
            plot(ax, t, obj.ResponseSignal);
            grid(ax, 'on');
            xlabel(ax, 'time (s)');
            ylabel(ax, 'V');
        end

        function plot_spectrum(obj, reset)
            % plot_spectrum(obj)  — plot power spectrum of ResponseSignal
            % plot_spectrum(obj, true) — clear axes
            arguments
                obj
                reset (1,1) logical = false
            end
            f  = stimgen.calibration.Engine.cal_fig_('signal');
            ax = subplot(2,1,2, 'Parent', f);
            if reset, cla(ax); drawnow; return; end
            if isempty(obj.ResponseSignal), return; end
            fs = obj.Fs;
            if fs == 0, return; end
            y   = obj.ResponseSignal;
            n   = numel(y);
            w   = flattopwin(n);
            [pxx, freqv] = periodogram(y, w, 2^nextpow2(n), fs, 'power');
            pxx_rms = sqrt(pxx);
            freqv   = freqv ./ 1000;
            plot(ax, freqv, obj.ReferenceLevel + 20*log10(pxx_rms ./ obj.MicSensitivity));
            grid(ax, 'on');
            set(ax, 'XScale', 'log');
            xlabel(ax, 'frequency (kHz)');
            ylabel(ax, 'level (dB SPL)');
            xlim(ax, [min(freqv) max(freqv)]);
            ylim(ax, [-20 120]);
        end

        function plot_transfer(~, type, tableData, reset)
            % plot_transfer(obj, type)
            % plot_transfer(obj, type, tableData) — overlay in-progress table
            % plot_transfer(obj, '', [], true)    — clear axes
            if nargin < 2, type = ''; end
            if nargin < 3, tableData = []; end
            if nargin < 4, reset = false; end
            f  = stimgen.calibration.Engine.cal_fig_('transfer');
            ax = axes('Parent', f);
            if reset, cla(ax); drawnow; return; end
            if isempty(type), return; end

            hold(ax, 'on');
            switch type
                case 'tone'
                    if ~isempty(tableData)
                        validIdx = ~isnan(tableData.spl_db);
                        x = tableData.x(validIdx) ./ 1000;
                        y = tableData.spl_db(validIdx);
                        plot(ax, x, y, 'x-r');
                        xlabel(ax, 'frequency (kHz)');
                    end
                case 'click'
                    if ~isempty(tableData)
                        validIdx = ~isnan(tableData.spl_db);
                        x = tableData.x(validIdx) .* 1e6;
                        y = tableData.spl_db(validIdx);
                        plot(ax, x, y, 'o-b');
                        xlabel(ax, 'duration (μs)');
                    end
                case 'swept_sine'
                    if ~isempty(tableData)
                        validIdx = ~isnan(tableData.spl_db);
                        x = tableData.x(validIdx) ./ 1000;
                        y = tableData.spl_db(validIdx);
                        loglog(ax, x, y, '^-g');
                        xlabel(ax, 'frequency (kHz)');
                    end
            end
            ylabel(ax, 'dB SPL');
            grid(ax, 'on');
            hold(ax, 'off');
        end

    end  % public methods

    % ------------------------------------------------------------------ %
    methods (Access = private)

        function assert_adapter_(obj)
            if isempty(obj.Adapter)
                error('stimgen:calibration:Engine:noAdapter', ...
                    'No HwAdapter attached. Provide an adapter to run calibrations.');
            end
        end

        function r = measure_(obj, signal, mode, options)
            % r = measure_(obj, signal, mode)
            % Play signal and return the requested measurement metric.
            %
            % Parameters:
            %   signal          - (1,:) double scaled excitation waveform
            %   mode            - "rms" | "peak" | "specfreq"
            %   StimFrequency   - double (required for "specfreq")
            %
            % Returns:
            %   r - scalar measurement in volts (RMS, peak, or spectral RMS)
            arguments
                obj
                signal  (1,:) double
                mode    (1,1) string {mustBeMember(mode,["rms","peak","specfreq"])}
                options.StimFrequency (1,1) double = 0
            end

            raw = obj.Adapter.play_and_record(signal);
            y   = obj.trim_response_(raw);
            obj.ResponseSignal = y;
            obj.ResponseTHD    = thd(y, obj.Fs);

            switch mode
                case "rms"
                    r = sqrt(mean(y.^2));
                case "peak"
                    r = max(abs(y));
                case "specfreq"
                    r = stimgen.calibration.Engine.spectral_rms(y, options.StimFrequency, obj.Fs);
            end
        end

        function [spl_db, voltage] = compute_spl_voltage_(obj, measurement, mode)
            % [spl_db, voltage] = compute_spl_voltage_(obj, measurement, mode)
            % Unified SPL and normative voltage calculation.
            %
            % For "peak" mode, converts peak amplitude to RMS equivalent
            % (÷√2) before computing dB SPL, giving a consistent reference.
            %
            % Parameters:
            %   measurement - double scalar measured by the microphone
            %   mode        - "rms" | "peak" | "specfreq"
            %
            % Returns:
            %   spl_db  - double measured sound level in dB SPL
            %   voltage - double output voltage to produce NormativeValue SPL
            if mode == "peak"
                m_rms = measurement / sqrt(2);
            else
                m_rms = measurement;
            end

            spl_db  = 20 * log10(m_rms / obj.MicSensitivity) + obj.ReferenceLevel;
            voltage = obj.ExcitationVoltage * 10 ^ ((obj.NormativeValue - spl_db) / 20);
        end

        function [noiseFloorDb, snrDb] = estimate_noise_snr_(~, y, fs, toneFreq)
            noiseFloorDb = nan;
            snrDb = nan;
            if nargin < 4
                toneFreq = nan;
            end
            if isempty(y) || fs <= 0
                return
            end

            n = numel(y);
            w = flattopwin(n);
            [pxx, f] = periodogram(y, w, 2^nextpow2(n), fs, 'power');
            pxx = max(pxx, eps);
            pxxDb = 10 * log10(pxx);
            noiseFloorDb = median(pxxDb, 'omitnan');

            if isfinite(toneFreq) && toneFreq > 0 && toneFreq < fs/2
                band = f >= toneFreq * 2^(-1/12) & f <= toneFreq * 2^(1/12);
                if any(band)
                    sigPow = sum(pxx(band));
                    noisePow = sum(pxx(~band)) * (nnz(band) / max(nnz(~band), 1));
                    snrDb = 10 * log10(sigPow / max(noisePow, eps));
                end
            else
                snrDb = prctile(pxxDb, 95) - noiseFloorDb;
            end
        end

        function [thdDb, h2Db, h3Db] = estimate_harmonics_(~, y, fs, fundamentalFreq)
            thdDb = nan;
            h2Db = nan;
            h3Db = nan;
            if isempty(y) || fs <= 0 || ~isfinite(fundamentalFreq) || fundamentalFreq <= 0 || fundamentalFreq >= fs/2
                return
            end

            n = numel(y);
            w = flattopwin(n);
            [pxx, f] = periodogram(y, w, 2^nextpow2(n), fs, 'power');
            pxx = max(pxx, eps);

            p1 = local_band_power_(pxx, f, fundamentalFreq);
            p2 = local_band_power_(pxx, f, 2 * fundamentalFreq);
            p3 = local_band_power_(pxx, f, 3 * fundamentalFreq);

            if p1 > 0
                h2Db = 10 * log10(p2 / p1);
                h3Db = 10 * log10(p3 / p1);
                thdDb = 10 * log10((p2 + p3) / p1);
            end

            function p = local_band_power_(pxxIn, fIn, fc)
                if fc <= 0 || fc >= fs/2
                    p = eps;
                    return
                end
                band = fIn >= fc * 2^(-1/16) & fIn <= fc * 2^(1/16);
                if ~any(band)
                    [~, idx] = min((fIn - fc).^2);
                    p = pxxIn(idx);
                else
                    p = sum(pxxIn(band));
                end
            end
        end

        function metrics = estimate_transfer_metrics_(~, x, y, fs)
            metrics = struct( ...
                'frequency_hz', [], ...
                'magnitude_db', [], ...
                'phase_deg', [], ...
                'impulse_response', [], ...
                'group_delay_samples', [], ...
                'group_delay_seconds', []);
            if isempty(x) || isempty(y) || fs <= 0
                return
            end

            n = min(numel(x), numel(y));
            x = x(1:n);
            y = y(1:n);
            nfft = 2^nextpow2(n);

            X = fft(x, nfft);
            Y = fft(y, nfft);
            H = Y ./ (X + eps);

            halfIdx = 1:(floor(nfft/2) + 1);
            freqHz = (halfIdx - 1)' .* (fs / nfft);
            Hh = H(halfIdx);
            magDb = 20 * log10(abs(Hh) + eps);

            phaseRad = unwrap(angle(Hh));
            phaseDeg = phaseRad * 180 / pi;
            omega = 2 * pi * freqHz / fs;
            dOmega = gradient(omega);
            dOmega = max(dOmega, eps);
            groupDelaySamples = -gradient(phaseRad) ./ dOmega;

            h = real(ifft(H, nfft));

            metrics.frequency_hz = freqHz;
            metrics.magnitude_db = magDb;
            metrics.phase_deg = phaseDeg;
            metrics.impulse_response = h(:);
            metrics.group_delay_samples = groupDelaySamples(:);
            metrics.group_delay_seconds = (groupDelaySamples(:) ./ fs);
        end

        function stats = repeatability_stats_(~, values)
            % values is expected to be [repeats x points].
            mu = mean(values, 1, 'omitnan');
            sigma = std(values, 0, 1, 'omitnan');
            stats = struct( ...
                'num_repeats', size(values, 1), ...
                'mean', mu(:), ...
                'std', sigma(:), ...
                'cv_percent', [], ...
                'overall_cv_percent', nan);
            stats.cv_percent = 100 * (stats.std ./ max(abs(stats.mean), eps));

            muAll = mean(stats.mean, 'omitnan');
            sigmaAll = mean(stats.std, 'omitnan');
            if isfinite(muAll)
                stats.overall_cv_percent = 100 * sigmaAll / max(abs(muAll), eps);
            end
        end

        function m = estimate_headroom_(~, excitation, response)
            fullScaleV = 10;
            m = struct( ...
                'assumedFullScaleV', fullScaleV, ...
                'excitationPeakV', nan, ...
                'excitationHeadroomDb', nan, ...
                'excitationClippingLikely', false, ...
                'responsePeakV', nan, ...
                'responseHeadroomDb', nan, ...
                'responseFlatTopFraction', nan, ...
                'responseClippingLikely', false);

            if ~isempty(excitation)
                exPeak = max(abs(excitation));
                m.excitationPeakV = exPeak;
                m.excitationHeadroomDb = 20 * log10(fullScaleV / max(exPeak, eps));
                m.excitationClippingLikely = exPeak >= fullScaleV;
            end

            if ~isempty(response)
                rspPeak = max(abs(response));
                m.responsePeakV = rspPeak;
                m.responseHeadroomDb = 20 * log10(fullScaleV / max(rspPeak, eps));

                tol = max(1e-8, 1e-5 * max(rspPeak, 1));
                flatTopFraction = mean(abs(abs(response) - rspPeak) <= tol);
                m.responseFlatTopFraction = flatTopFraction;
                m.responseClippingLikely = (rspPeak >= fullScaleV) || (flatTopFraction > 0.01);
            end
        end

        function out = aggregate_headroom_(~, metricsArray)
            out = struct( ...
                'assumedFullScaleV', nan, ...
                'excitationPeakV', nan, ...
                'excitationHeadroomDb', nan, ...
                'excitationClippingLikely', false, ...
                'responsePeakV', nan, ...
                'responseHeadroomDb', nan, ...
                'responseFlatTopFraction', nan, ...
                'responseClippingLikely', false);
            if isempty(metricsArray)
                return
            end

            out.assumedFullScaleV = metricsArray(1).assumedFullScaleV;
            out.excitationPeakV = mean([metricsArray.excitationPeakV], 'omitnan');
            out.excitationHeadroomDb = mean([metricsArray.excitationHeadroomDb], 'omitnan');
            out.excitationClippingLikely = any([metricsArray.excitationClippingLikely]);
            out.responsePeakV = mean([metricsArray.responsePeakV], 'omitnan');
            out.responseHeadroomDb = mean([metricsArray.responseHeadroomDb], 'omitnan');
            out.responseFlatTopFraction = mean([metricsArray.responseFlatTopFraction], 'omitnan');
            out.responseClippingLikely = any([metricsArray.responseClippingLikely]);
        end

        function y = trim_response_(obj, y)
            % y = trim_response_(obj, y)
            % Remove trailing buffer padding and trim leading propagation delay.
            % Only contiguous trailing zeros are stripped; mid-signal zeros
            % (valid zero crossings) are preserved.
            lastNZ = find(y ~= 0, 1, 'last');
            if ~isempty(lastNZ)
                y = y(1:lastNZ);
            end

            % Clip first ~3 ms: acoustic propagation delay at ~343 m/s.
            trimSamps = round(3e-3 * obj.Fs);
            if numel(y) > trimSamps
                y = y(trimSamps + 1 : end);
            end
        end

        function cd = commit_cal_data_(obj)
            % Return a valid CalibrationData struct, preserving any existing
            % fields (tone, click, filter) so incremental sweeps accumulate.
            if isstruct(obj.CalibrationData)
                cd = obj.CalibrationData;
            else
                cd = struct( ...
                    'filter',        [], ...
                    'filterGrpDelay', 0);
            end
        end

        function t = empty_table_(~, n)
            t = struct('x', nan(1,n), 'measurement', nan(1,n), ...
                       'spl_db', nan(1,n), 'voltage', nan(1,n));
        end

        function restore_from_struct_(obj, s)
            % restore_from_struct_(obj, s)
            % Populate engine properties from a saved .esgc struct.
            obj.CalibrationData      = s.CalibrationData;
            obj.MicSensitivity       = s.MicSensitivity;
            obj.NormativeValue       = s.NormativeValue;
            obj.ReferenceLevel       = s.ReferenceLevel;
            obj.ReferenceFrequency   = s.ReferenceFrequency;
            obj.ExcitationVoltage    = s.ExcitationVoltage;
            obj.CalibrationTimestamp = s.CalibrationTimestamp;
        end

    end  % private methods

    % ------------------------------------------------------------------ %
    methods (Static)

        function eng = load(ffn)
            % eng = stimgen.calibration.Engine.load()
            % eng = stimgen.calibration.Engine.load(ffn)
            %
            % Load a .esgc calibration file and return an Engine with no
            % adapter attached. Suitable for offline compute_adjusted_voltage
            % use. Attach an adapter to run new calibrations.
            %
            % Parameters:
            %   ffn - full file path (char, optional); prompts if omitted
            %
            % Returns:
            %   eng - stimgen.calibration.Engine
            arguments
                ffn (1,:) char = ''
            end
            if isempty(ffn)
                pn = getpref('StimCalibration', 'path', pwd);
                [fn, pn] = uigetfile( ...
                    {'*.esgc','EPsych Stim Calibration (*.esgc)'}, ...
                    'Load Calibration', pn);
                if isequal(fn, 0), eng = []; return; end
                ffn = fullfile(pn, fn);
                setpref('StimCalibration', 'path', pn);
            end

            [~, ~, ext] = fileparts(ffn);
            if ~strcmpi(ext, '.esgc')
                error('stimgen:calibration:Engine:wrongFormat', ...
                    ['Expected a .esgc file. Old .sgc files are not supported — ' ...
                    'please recalibrate and save to a new .esgc file.']);
            end

            s = load(ffn, '-mat');
            if ~isfield(s, 'version')
                error('stimgen:calibration:Engine:missingVersion', ...
                    'File "%s" is missing the schema version field.', ffn);
            end

            eng = stimgen.calibration.Engine();
            eng.restore_from_struct_(s);

            if isstruct(eng.CalibrationData)
                ts = eng.CalibrationTimestamp;
                if isequal(ts, datetime(""))
                    vprintf(0, 'Loaded calibration: "%s" (timestamp unknown)', ffn);
                else
                    vprintf(0, 'Loaded calibration: "%s" from %s', ffn, string(ts));
                end
            end
        end

        function r = spectral_rms(x, freq, fs)
            % r = stimgen.calibration.Engine.spectral_rms(x, freq, fs)
            % Estimate signal power at a single frequency via periodogram.
            % Uses a 1/8-octave band centred on the nearest bin to freq.
            %
            % Parameters:
            %   x    - (1,:) double time-domain signal
            %   freq - double centre frequency in Hz
            %   fs   - double sample rate in Hz
            %
            % Returns:
            %   r - double RMS amplitude at freq (volts)
            n = numel(x);
            w = flattopwin(n);
            [pxx, f] = periodogram(x, w, 2^nextpow2(n), fs, 'power');
            [~, cidx] = min((f - freq).^2);
            band = f >= f(cidx) * 2^(-1/8) & f <= f(cidx) * 2^(1/8);
            [~, lidx] = max(pxx(band));
            idx = find(band);
            r = sqrt(pxx(idx(lidx)));
        end

    end  % static methods

    methods (Static, Access = private)
        function f = cal_fig_(name)
            f = findobj('Type', 'figure', 'Name', name);
            if isempty(f)
                f = figure('Name', name, 'NumberTitle', 'off');
            end
            figure(f);
        end

        function s = rmfield_safe_(s, fname)
            if isstruct(s) && isfield(s, fname)
                s = rmfield(s, fname);
            end
        end
    end

end  % classdef
