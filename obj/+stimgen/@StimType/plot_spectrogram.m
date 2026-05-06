function h = plot_spectrogram(obj, ax, nfft, overlap, window)
% plot_spectrogram(obj)
% plot_spectrogram(obj, ax)
% plot_spectrogram(obj, ax, nfft)
% plot_spectrogram(obj, ax, nfft, overlap)
% plot_spectrogram(obj, ax, nfft, overlap, window)
% Plot a power spectrogram of the current Signal using spectrogram().
%
% Parameters:
%   ax      - Target axes handle (default: gca).
%   nfft    - FFT length in samples (default: 256).
%   overlap - Number of overlapping samples (default: nfft/2).
%   window  - Window vector or length scalar (default: hamming(nfft)).
%
% Returns:
%   h - Handle to the image returned by imagesc().

if nargin < 2 || isempty(ax),      ax = gca;                  end
if nargin < 3 || isempty(nfft),    nfft = 256;                end
if nargin < 4 || isempty(overlap), overlap = floor(nfft/2);   end
if nargin < 5 || isempty(window),  window = hamming(nfft);    end

if isempty(obj.Signal)
    obj.call_update_signal_with_variant_cycle_();
end

fsValue = double(obj.get_selected_property_value_("Fs"));
[~, ~, ~, ps] = spectrogram(obj.Signal, window, overlap, nfft, fsValue, 'power');
freqVec = linspace(0, fsValue/2, size(ps,1));
timeVec = linspace(0, obj.Duration, size(ps,2));

h = imagesc(ax, timeVec, freqVec, 10*log10(ps));
axis(ax, 'xy');
xlabel(ax, 'time (s)');
ylabel(ax, 'frequency (Hz)');
cb = colorbar(ax);
cb.Label.String = 'Power (dB)';
