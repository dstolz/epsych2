function [logL, thetaGrid, slopeGrid, ci] = computeLogLikelihood_(obj, stimLevels, responses)
% [logL, thetaGrid, slopeGrid, ci] = computeLogLikelihood_(obj, stimLevels, responses)
% Compute the normalized log-likelihood over a grid of candidate threshold
% values (and optionally slope values), then derive a profile log-likelihood
% confidence interval on the threshold.
%
% Parameters:
%   stimLevels - (1 x nTrials) row vector of presented stimulus levels
%   responses  - (1 x nTrials) binary row vector (1 = positive, 0 = negative)
%
% Returns:
%   logL      - Normalized log-likelihood (max = 0). Row vector (1 x nTheta)
%               when EstimateSlope=false; matrix (nSlope x nTheta) otherwise.
%   thetaGrid - Threshold grid. Row vector (1 x nTheta) or meshgrid matrix.
%   slopeGrid - Slope grid (nSlope x nTheta), or [] when EstimateSlope=false.
%   ci        - [lower upper] profile log-likelihood confidence interval on threshold.

nTrials  = numel(stimLevels);
thetaVec = linspace(obj.Range(1), obj.Range(2), obj.GridResolution);

if obj.EstimateSlope
    slopeVec = linspace(obj.SlopeRange(1), obj.SlopeRange(2), obj.SlopeGridResolution);
    [thetaGrid, slopeGrid] = meshgrid(thetaVec, slopeVec);  % (nSlope x nTheta)

    % Expand arrays for broadcasting: (nSlope x nTheta x nTrials)
    thetaExp = reshape(thetaGrid, obj.SlopeGridResolution, obj.GridResolution, 1);
    slopeExp = reshape(slopeGrid, obj.SlopeGridResolution, obj.GridResolution, 1);
    stimExp  = reshape(stimLevels, 1, 1, nTrials);
    respExp  = reshape(responses,  1, 1, nTrials);

    P    = obj.evaluatePsychFn_(stimExp, thetaExp, slopeExp);  % (nSlope x nTheta x nTrials)
    logL = sum(respExp .* log(P) + (1 - respExp) .* log(1 - P), 3);  % (nSlope x nTheta)
else
    thetaGrid = thetaVec;  % (1 x nTheta)
    slopeGrid = [];

    % Expand arrays for broadcasting: (nTrials x nTheta)
    thetaExp = reshape(thetaGrid,  1,       obj.GridResolution);  % (1 x nTheta)
    stimExp  = reshape(stimLevels, nTrials, 1);                   % (nTrials x 1)
    respExp  = reshape(responses,  nTrials, 1);                   % (nTrials x 1)

    P    = obj.evaluatePsychFn_(stimExp, thetaExp, obj.Slope);  % (nTrials x nTheta)
    logL = sum(respExp .* log(P) + (1 - respExp) .* log(1 - P), 1);  % (1 x nTheta)
end

% Normalize: shift so max = 0 for numerical stability and CI thresholding
logL = logL - max(logL(:));

% Profile log-likelihood CI: threshold where logL drops by chi2inv(level,1)/2
logL_thresh = -chi2inv(obj.ConfidenceLevel, 1) / 2;

if obj.EstimateSlope
    % Marginalize over slope via profile (max over rows) to get (1 x nTheta) profile
    logL_profile = max(logL, [], 1);
    ciVec = thetaVec;
else
    logL_profile = logL;
    ciVec = thetaGrid;
end

firstIdx = find(logL_profile >= logL_thresh, 1, 'first');
lastIdx  = find(logL_profile >= logL_thresh, 1, 'last');
if isempty(firstIdx) || isempty(lastIdx)
    ci = obj.Range;
else
    ci = [ciVec(firstIdx), ciVec(lastIdx)];
end
