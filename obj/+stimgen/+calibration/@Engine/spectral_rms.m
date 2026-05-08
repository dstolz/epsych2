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
