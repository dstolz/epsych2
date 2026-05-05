function v = compute_adjusted_voltage(obj, type, value, level)
% v = compute_adjusted_voltage(obj, type, value, level)
%
% Proxy to stimgen.calibration.Engine.compute_adjusted_voltage.
% Interpolates the calibration LUT and scales to the requested sound level.
%
% Parameters:
%   obj   - stimgen.StimCalibration
%   type  - "tone", "click", "swept_sine", "filter", or "noise"
%   value - frequency (Hz) for "tone"/"swept_sine"/"filter"/"noise";
%           duration (s) for "click"
%   level - target sound level in dB SPL
%
% Returns:
%   v - required output voltage
v = obj.Engine.compute_adjusted_voltage(type, value, level);

