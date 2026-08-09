function P = evaluatePsychFn_(obj, x, theta, slope)
% P = evaluatePsychFn_(obj, x, theta, slope)
% Evaluate the generalized psychometric function P(x; theta, slope) with
% guess rate (gamma) and lapse rate (lambda) applied.
% All array inputs are broadcast-compatible so this method can be called
% with scalar, vector, or multi-dimensional arrays simultaneously.
%
% Parameters:
%   x     - Stimulus levels (any shape, broadcast-compatible with theta/slope)
%   theta - Location/scale parameter (any shape, broadcast-compatible)
%   slope - Steepness parameter (any shape, broadcast-compatible)
%
% Returns:
%   P - Response probability clamped to [eps, 1-eps]

gamma  = obj.GuessRate;
lambda = obj.LapseRate;

switch obj.PsychometricFunction
    case "Logistic"
        baseCdf = 1 ./ (1 + exp(-slope .* (x - theta)));
    case "Normal"
        baseCdf = normcdf(x, theta, 1 ./ slope);
    case "Weibull"
        baseCdf = 1 - exp(-(x ./ theta) .^ slope);
end

P = gamma + (1 - gamma - lambda) .* baseCdf;
P = max(eps, min(1 - eps, P));
