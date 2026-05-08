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
