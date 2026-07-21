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
    stimgen.util.vprintf(1, 'Analyzing swept sine response at %d frequencies (%d averages)...', n, repeatCount);
    for rep = 1:repeatCount
        stimgen.util.vprintf(1, '[%d/%d] Capturing swept sine response', rep, repeatCount);
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
    stimgen.util.vprintf(0, 2, 'Swept sine calibration aborted: %s', ME.message);
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

stimgen.util.vprintf(1, 'Swept sine calibration complete. THD: %.2f dB', obj.ResponseTHD);
end
