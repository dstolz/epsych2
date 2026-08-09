function [logPosterior, alphaVec, betaVec, lapseVec] = computePosterior_(obj, stimLevels, responses)
% [logPosterior, alphaVec, betaVec, lapseVec] = computePosterior_(obj, stimLevels, responses)
% Compute the 3D Bayesian log-posterior over the (alpha x beta x lambda) grid
% from the active trial history. Combines a factored Gaussian log-prior with
% the accumulated log-likelihood across all provided stimulus-response pairs.
% All computation is fully vectorized with no per-trial loops.
%
% Parameters:
%   stimLevels - (1 x nTrials) row vector of presented signal strengths.
%   responses  - (1 x nTrials) binary row vector (1 = correct, 0 = incorrect).
%
% Returns:
%   logPosterior - (nAlpha x nBeta x nLapse) unnormalized log-posterior.
%   alphaVec     - (1 x nAlpha) alpha grid values.
%   betaVec      - (1 x nBeta) beta grid values.
%   lapseVec     - (1 x nLapse) lambda grid values.

nA = obj.AlphaResolution;
nB = obj.BetaResolution;
nL = obj.LapseResolution;

alphaVec = linspace(obj.AlphaRange(1), obj.AlphaRange(2), nA);
betaVec  = linspace(obj.BetaRange(1),  obj.BetaRange(2),  nB);
lapseVec = linspace(obj.LapseRange(1), obj.LapseRange(2), nL);

% Factored 3D Gaussian log-prior:  log P(alpha,beta,lapse) = log N(alpha) + log N(beta) + log N(lapse)
% Shapes broadcast to (nA x nB x nL) via implicit expansion.
logPA = reshape(-0.5 * ((alphaVec - obj.AlphaPriorMean) / obj.AlphaPriorStd).^2, [nA 1 1]);
logPB = reshape(-0.5 * ((betaVec  - obj.BetaPriorMean)  / obj.BetaPriorStd ).^2, [1 nB 1]);
logPL = reshape(-0.5 * ((lapseVec - obj.LapsePriorMean) / obj.LapsePriorStd ).^2, [1 1 nL]);

logPrior = logPA + logPB + logPL;  % (nA x nB x nL)

nTrials = numel(stimLevels);
if nTrials == 0
    logPosterior = logPrior;
    return
end

% Reshape grids and data for (nTrials x nA x nB x nL) broadcasting.
% Each dimension is independent, allowing a single vectorized P evaluation.
aExp = reshape(alphaVec,   [1 nA 1  1 ]);
bExp = reshape(betaVec,    [1 1  nB 1 ]);
lExp = reshape(lapseVec,   [1 1  1  nL]);
xExp = reshape(stimLevels, [nTrials 1 1 1]);
rExp = reshape(responses,  [nTrials 1 1 1]);

% P: (nTrials x nA x nB x nL)
P = obj.evaluatePsychFn_(xExp, aExp, bExp, lExp);

% Sum log-likelihood over trials: result is (1 x nA x nB x nL), then squeeze to (nA x nB x nL)
logL = sum(rExp .* log(P) + (1 - rExp) .* log(1 - P), 1);
logL = reshape(logL, [nA nB nL]);

logPosterior = logPrior + logL;
