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
        stimgen.util.vprintf(1, '[%d/%d] Calibrating click %.2f μs', i, n, durs(i)*1e6);
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
    stimgen.util.vprintf(0, 2, 'Click calibration aborted: %s', ME.message);
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
