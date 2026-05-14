function sweetPoints = computeSweetPoints_(obj, alphaML, betaML, lapseML)
% sweetPoints = computeSweetPoints_(obj, alphaML, betaML, lapseML)
% Numerically find the sweet-point signal strengths — the stimulus levels that
% minimize the expected variance of each psychometric function parameter.
%
% The expected variance of parameter theta from a single trial is:
%   sigma^2_theta(x) = P(x)(1-P(x)) / (dP/d_theta)^2
%
% Sweet points are the signal strengths x where each sigma^2 is minimized.
% Parameter derivatives are computed via central finite differences.
%
% For the Logistic function, four sweet points are returned (in ascending order):
%   1. Lower beta-sweet  (minimum of sigma^2_beta below alphaML)
%   2. Alpha-sweet       (minimum of sigma^2_alpha)
%   3. Upper beta-sweet  (minimum of sigma^2_beta above alphaML)
%   4. Lambda-sweet      (MaxSignalStrength, proxy for sigma^2_lambda minimum)
%
% For the Weibull function, three sweet points are returned (ascending order):
%   1. K-sweet   (minimum of sigma^2_alpha, where alpha = k)
%   2. Beta-sweet (minimum of sigma^2_beta)
%   3. Lambda-sweet (MaxSignalStrength proxy)
%
% Parameters:
%   alphaML - ML estimate of alpha (threshold for Logistic, k scale for Weibull).
%   betaML  - ML estimate of beta (slope).
%   lapseML - ML estimate of lambda (lapse rate).
%
% Returns:
%   sweetPoints - Column vector of sweet-point signal strengths in ascending order.

xGrid = linspace(obj.AlphaRange(1), obj.MaxSignalStrength, obj.SweetPointGridResolution);

% Step sizes for central-difference derivatives.
% Use a relative step (1e-3 of |param|) with a minimum absolute floor.
hAlpha = max(1e-6, abs(alphaML) * 1e-3);
hBeta  = max(1e-6, abs(betaML)  * 1e-3);

% Evaluate P at perturbed parameter values over xGrid.
% dP/dLapse is not needed: sigma^2_lambda is monotone in x so its sweet
% point is always MaxSignalStrength; no numerical optimization is required.
P0  = obj.evaluatePsychFn_(xGrid, alphaML,          betaML,         lapseML);
Pap = obj.evaluatePsychFn_(xGrid, alphaML + hAlpha, betaML,         lapseML);
Pam = obj.evaluatePsychFn_(xGrid, alphaML - hAlpha, betaML,         lapseML);
Pbp = obj.evaluatePsychFn_(xGrid, alphaML,          betaML + hBeta, lapseML);
Pbm = obj.evaluatePsychFn_(xGrid, alphaML,          betaML - hBeta, lapseML);

dPdAlpha = (Pap - Pam) / (2 * hAlpha);
dPdBeta  = (Pbp - Pbm) / (2 * hBeta);

% Binomial variance P*(1-P); guarded against exactly 0 or 1
pq = P0 .* (1 - P0);

% Expected variances; eps guard prevents division by zero where derivative vanishes
sigma2Alpha = pq ./ max(eps, dPdAlpha .^ 2);
sigma2Beta  = pq ./ max(eps, dPdBeta  .^ 2);

% Alpha-sweet: global minimum of sigma2Alpha
[~, iAlpha] = min(sigma2Alpha);
x_alphaSP   = xGrid(iAlpha);

% Lambda-sweet: proxy at the maximum signal strength (sigma^2_lambda is monotone decreasing)
x_lambdaSP = obj.MaxSignalStrength;

if strcmp(obj.PsychometricFunction, "Logistic")
    % Beta-sweet has two local minima on either side of alphaML because
    % sigma^2_beta is singular (dP/dbeta = 0) at x = alphaML.
    % Search each half of the x grid separately.
    maskLow  = xGrid < alphaML;
    maskHigh = xGrid > alphaML;

    if any(maskLow)
        s2bLow = sigma2Beta(maskLow);
        xLow   = xGrid(maskLow);
        [~, i] = min(s2bLow);
        x_betaLow = xLow(i);
    else
        x_betaLow = xGrid(1);
    end

    if any(maskHigh)
        s2bHigh = sigma2Beta(maskHigh);
        xHigh   = xGrid(maskHigh);
        [~, i] = min(s2bHigh);
        x_betaHigh = xHigh(i);
    else
        x_betaHigh = xGrid(end);
    end

    % Return in ascending order: [lowerBeta, alpha, upperBeta, lambda]
    sweetPoints = sort([x_betaLow; x_alphaSP; x_betaHigh; x_lambdaSP]);

else  % Weibull: sigma^2_beta has a single minimum; sigma^2_alpha (for k) also has a single minimum
    [~, iBeta] = min(sigma2Beta);
    x_betaSP   = xGrid(iBeta);

    sweetPoints = sort([x_alphaSP; x_betaSP; x_lambdaSP]);
end
