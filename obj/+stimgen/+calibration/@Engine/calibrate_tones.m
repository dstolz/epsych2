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
        stimgen.util.vprintf(1, '[%d/%d] Calibrating tone %.3f kHz', i, n, freqs(i)/1000);
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
    stimgen.util.vprintf(0, 2, 'Tone calibration aborted: %s', ME.message);
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
