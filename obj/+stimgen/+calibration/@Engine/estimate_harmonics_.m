function [thdDb, h2Db, h3Db] = estimate_harmonics_(~, y, fs, fundamentalFreq)
thdDb = nan;
h2Db = nan;
h3Db = nan;
if isempty(y) || fs <= 0 || ~isfinite(fundamentalFreq) || fundamentalFreq <= 0 || fundamentalFreq >= fs/2
    return
end

n = numel(y);
w = flattopwin(n);
[pxx, f] = periodogram(y, w, 2^nextpow2(n), fs, 'power');
pxx = max(pxx, eps);

p1 = local_band_power_(pxx, f, fundamentalFreq);
p2 = local_band_power_(pxx, f, 2 * fundamentalFreq);
p3 = local_band_power_(pxx, f, 3 * fundamentalFreq);

if p1 > 0
    h2Db = 10 * log10(p2 / p1);
    h3Db = 10 * log10(p3 / p1);
    thdDb = 10 * log10((p2 + p3) / p1);
end

function p = local_band_power_(pxxIn, fIn, fc)
    if fc <= 0 || fc >= fs/2
        p = eps;
        return
    end
    band = fIn >= fc * 2^(-1/16) & fIn <= fc * 2^(1/16);
    if ~any(band)
        [~, idx] = min((fIn - fc).^2);
        p = pxxIn(idx);
    else
        p = sum(pxxIn(band));
    end
end
end
