function P = evaluatePsychFn_(obj, x, alpha, beta, lapse)
% P = evaluatePsychFn_(obj, x, alpha, beta, lapse)
% Evaluate the psychometric function P(x; alpha, beta, GuessRate, lapse)
% for any broadcast-compatible array shapes. GuessRate (gamma) is fixed at
% obj.GuessRate. Lapse (lambda) is a variable input, not obj.LapseRate, since
% it is estimated rather than fixed in the MLP procedure.
%
% For Logistic:  P = gamma + (1-gamma-lapse) / (1 + exp(-beta*(x-alpha)))
%   where alpha is the threshold (location parameter).
%
% For Weibull:   P = gamma + (1-gamma-lapse) * (1 - alpha^(x^beta))
%   where alpha = k is the scale parameter (0 < k < 1), as in Shen &
%   Richards (2012) Appendix Eq. A4. At x=0, P=gamma; as x->inf, P->1-lapse.
%
% Parameters:
%   x     - Stimulus signal strength (any shape, broadcast-compatible).
%   alpha - Threshold (Logistic) or scale k (Weibull), broadcast-compatible.
%   beta  - Slope parameter, broadcast-compatible.
%   lapse - Lapse rate lambda, broadcast-compatible.
%
% Returns:
%   P - Response probability clamped to [eps, 1-eps] to guard log operations.

gamma = obj.GuessRate;

switch obj.PsychometricFunction
    case "Logistic"
        baseCdf = 1 ./ (1 + exp(-beta .* (x - alpha)));

    case "Weibull"
        % P = gamma + (1-gamma-lapse)(1 - k^(x^beta))
        % Equivalent to the standard Weibull with k = exp(-1/theta^beta).
        % Clamp alpha (= k) to (0, 1) to keep log(k) defined and k^(...) in (0,1).
        k = max(eps, min(1 - eps, alpha));
        baseCdf = 1 - exp((x .^ beta) .* log(k));
end

P = gamma + (1 - gamma - lapse) .* baseCdf;
P = max(eps, min(1 - eps, P));
