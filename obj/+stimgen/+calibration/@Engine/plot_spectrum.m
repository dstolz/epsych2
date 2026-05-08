function plot_spectrum(obj, reset)
% plot_spectrum(obj)  - plot power spectrum of ResponseSignal
% plot_spectrum(obj, true) - clear axes
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
