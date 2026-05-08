function m = estimate_headroom_(~, excitation, response)
fullScaleV = 10;
m = struct( ...
    'assumedFullScaleV', fullScaleV, ...
    'excitationPeakV', nan, ...
    'excitationHeadroomDb', nan, ...
    'excitationClippingLikely', false, ...
    'responsePeakV', nan, ...
    'responseHeadroomDb', nan, ...
    'responseFlatTopFraction', nan, ...
    'responseClippingLikely', false);

if ~isempty(excitation)
    exPeak = max(abs(excitation));
    m.excitationPeakV = exPeak;
    m.excitationHeadroomDb = 20 * log10(fullScaleV / max(exPeak, eps));
    m.excitationClippingLikely = exPeak >= fullScaleV;
end

if ~isempty(response)
    rspPeak = max(abs(response));
    m.responsePeakV = rspPeak;
    m.responseHeadroomDb = 20 * log10(fullScaleV / max(rspPeak, eps));

    tol = max(1e-8, 1e-5 * max(rspPeak, 1));
    flatTopFraction = mean(abs(abs(response) - rspPeak) <= tol);
    m.responseFlatTopFraction = flatTopFraction;
    m.responseClippingLikely = (rspPeak >= fullScaleV) || (flatTopFraction > 0.01);
end
end
