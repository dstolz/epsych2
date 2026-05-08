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
