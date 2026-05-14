function x = invertPsychFn_(obj, P_target, theta, slope)
% x = invertPsychFn_(obj, P_target, theta, slope)
% Invert the psychometric function to find the stimulus level x such that
% P(x; theta, slope) = P_target, accounting for GuessRate and LapseRate.
% Returns NaN when P_target is unreachable given the configured asymptotes.
%
% Parameters:
%   P_target - Target response probability
%   theta    - Location/scale parameter estimate
%   slope    - Slope parameter
%
% Returns:
%   x - Stimulus level yielding P_target, or NaN if P_target is unreachable.
%
% Note: For Weibull, theta is the scale parameter (the 63.2% base-CDF point),
% so ThresholdAtTarget will differ from ThresholdEstimate even when
% TargetProbability=0.5, GuessRate=0, and LapseRate=0.

gamma  = obj.GuessRate;
lambda = obj.LapseRate;

% Rescale to the base CDF argument; valid range is (0, 1) exclusive
p_norm = (P_target - gamma) / (1 - gamma - lambda);

if p_norm <= 0 || p_norm >= 1
    vprintf(0, 1, ...
        'BestPEST: TargetProbability %.4g is unreachable given GuessRate=%.4g and LapseRate=%.4g.\n', ...
        P_target, gamma, lambda);
    x = NaN;
    return
end

switch obj.PsychometricFunction
    case "Logistic"
        x = theta + log(p_norm / (1 - p_norm)) / slope;
    case "Normal"
        x = theta + norminv(p_norm) / slope;
    case "Weibull"
        x = theta * (-log(1 - p_norm))^(1/slope);
end
