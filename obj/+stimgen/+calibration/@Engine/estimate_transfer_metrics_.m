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
Hh = Hh(:);
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
