% demo_adaptive_threshold
% Generalized simulation and test script for psychophysics.MLP and psychophysics.BestPEST.
% Simulates an adaptive threshold-tracking experiment using artificial observer
% responses drawn from a known psychometric function. Compares the estimated
% threshold and fitted psychometric function to ground truth.
%
% Usage: set the Configuration block below, then run the script.
%
% Supported methods:
%   'MLP'       - Three-parameter Bayesian MLP (Shen & Richards 2012)
%   'BestPEST'  - Maximum-likelihood Best PEST (Pentland 1980)
%
% Configuration:
%   METHOD          - 'MLP' or 'BestPEST'
%   TRUE_THRESHOLD  - Ground-truth threshold used to generate artificial responses
%   TRUE_SLOPE      - Ground-truth slope of the psychometric function
%   TRUE_LAPSE      - Ground-truth lapse rate (upper asymptote offset)
%   GUESS_RATE      - Fixed lower asymptote gamma (0 = yes/no, 0.5 = 2-AFC)
%   LEVEL_RANGE     - [min max] search range for the stimulus parameter
%   N_TRIALS        - Maximum number of stimulus trials
%   STOP_CI_WIDTH   - BestPEST early-stop criterion on CI width; Inf = run all
%   RNG_SEED        - Integer for reproducibility; [] to skip seeding

% -------------------------------------------------------------------------
% Configuration
% -------------------------------------------------------------------------
% METHOD         = 'MLP';  % 'MLP' or 'BestPEST'
METHOD         = 'BestPEST';  % 'MLP' or 'BestPEST'
TRUE_THRESHOLD = -20;         % true detection threshold
TRUE_SLOPE     = .5;          % psychometric slope
TRUE_LAPSE     = 0.01;        % lapse rate (upper asymptote offset)
GUESS_RATE     = 0;           % lower asymptote (0.5 for 2-AFC; 0 for yes-no)
LEVEL_RANGE    = [-40 0];     % [min max] dB search range
N_TRIALS       = 100;         % maximum stimulus trials
STOP_CI_WIDTH  = inf;         % BestPEST early-stop CI width (dB); Inf = disabled
RNG_SEED       = [];          % reproducible RNG; set [] to skip

% -------------------------------------------------------------------------
% RNG
% -------------------------------------------------------------------------
if ~isempty(RNG_SEED)
    rng(RNG_SEED);
end

% -------------------------------------------------------------------------
% True psychometric function (logistic):
%   P(x) = gamma + (1 - gamma - lambda) / (1 + exp(-beta*(x - alpha)))
% -------------------------------------------------------------------------
truePsychFn = @(x) GUESS_RATE + (1 - GUESS_RATE - TRUE_LAPSE) ./ ...
    (1 + exp(-TRUE_SLOPE .* (x - TRUE_THRESHOLD)));

% -------------------------------------------------------------------------
% RespCode helpers — encode Hit/Miss using epsych.BitMask bit positions.
%   bitset(uint32(0), p) sets bit at position p (1-indexed from LSB).
%   epsych.BitMask.decode uses bitget(rc, p), so position p = enum value.
% -------------------------------------------------------------------------
HIT_CODE  = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS_CODE = bitset(uint32(0), uint32(epsych.BitMask.Miss));

% -------------------------------------------------------------------------
% Preallocate history arrays and empty DATA struct
% -------------------------------------------------------------------------
DATA            = struct('Level', {}, 'RespCode', {}, 'TrialType', {});
levelHistory    = nan(1, N_TRIALS);
responseHistory = false(1, N_TRIALS);
estHistory      = nan(1, N_TRIALS);   % running threshold estimate per trial
ciHistory       = nan(N_TRIALS, 2);   % BestPEST CI bounds per trial


% -------------------------------------------------------------------------
% Helper: construct estimator from accumulated DATA struct array.
% Config variables are passed explicitly because local functions in scripts
% do not share the script workspace.
% -------------------------------------------------------------------------
function est = buildEstimator(data, method, levelRange, guessRate, trueSlope, trueLapse)
switch upper(method)
    case 'MLP'
        est = psychophysics.MLP(data, 'Level', ...
            AlphaRange     = levelRange, ...
            GuessRate      = guessRate, ...
            BetaPriorMean  = trueSlope, ...
            SweetPointRule = 'UpDown');
    case 'BESTPEST'
        est = psychophysics.BestPEST(data, 'Level', ...
            Range             = levelRange, ...
            GuessRate         = guessRate, ...
            LapseRate         = trueLapse, ...
            TargetProbability = 0.5, ...
            EstimateSlope     = false, ...
            Slope             = trueSlope);
    otherwise
        error('demo_adaptive_threshold:unknownMethod', ...
            'METHOD must be ''MLP'' or ''BestPEST''.');
end
end

% -------------------------------------------------------------------------
% Adaptive simulation loop
% -------------------------------------------------------------------------
fprintf('\n=== demo_adaptive_threshold: %s ===\n', METHOD);
fprintf('True: threshold = %.2f  |  slope = %.2f  |  lapse = %.2f  |  guess = %.2f\n\n', ...
    TRUE_THRESHOLD, TRUE_SLOPE, TRUE_LAPSE, GUESS_RATE);

nDone = 0;
ci    = [];

for iTrial = 1:N_TRIALS

    % Build estimator from data accumulated so far (before this trial)
    est       = buildEstimator(DATA, METHOD, LEVEL_RANGE, GUESS_RATE, TRUE_SLOPE, TRUE_LAPSE);
    nextLevel = est.Results.NextLevel;

    % Save running estimate (based on trials 1..iTrial-1).
    % Estimates are [] until enough data have accumulated; leave NaN in history.
    switch upper(METHOD)
        case 'MLP'
            if ~isempty(est.Results.AlphaEstimate)
                estHistory(iTrial) = est.Results.AlphaEstimate;
            end
        case 'BESTPEST'
            if ~isempty(est.Results.ThresholdEstimate)
                estHistory(iTrial) = est.Results.ThresholdEstimate;
            end
            ci = est.Results.ConfidenceInterval;
            if ~isempty(ci)
                ciHistory(iTrial, :) = ci;
            end
    end

    % Simulate observer response using the true psychometric function
    pCorrect  = truePsychFn(nextLevel);
    responded = rand() < pCorrect;

    respCode = HIT_CODE  * uint32( responded) + ...
        MISS_CODE * uint32(~responded);

    % Append trial to DATA (TrialType=0 identifies it as a stimulus trial)
    newTrial.Level     = nextLevel;
    newTrial.RespCode  = respCode;
    newTrial.TrialType = 0;
    DATA(end+1)        = newTrial;

    levelHistory(iTrial)    = nextLevel;
    responseHistory(iTrial) = responded;
    nDone                   = iTrial;

    % BestPEST early-stop: require at least 10 trials before checking
    if strcmpi(METHOD, 'BESTPEST') && ~isempty(ci) && all(isfinite(ci))
        if diff(ci) < STOP_CI_WIDTH && iTrial >= 10
            fprintf('Early stop at trial %d: CI width = %.3f < %.3f\n', ...
                iTrial, diff(ci), STOP_CI_WIDTH);
            % break
            fprintf('Resetting BESTPEST\n')
            est.reset;
            nextLevel = max(LEVEL_RANGE);
            % est.Results.NextLevel = nextLevel;
        end
    end

    if mod(iTrial, 5) == 0
        fprintf('  Trial %3d  |  level = %6.2f  |  response = %d\n', ...
            iTrial, nextLevel, responded);
    end
end

% Trim histories to the actual run length
levelHistory    = levelHistory(1:nDone);
responseHistory = responseHistory(1:nDone);
estHistory      = estHistory(1:nDone);
ciHistory       = ciHistory(1:nDone, :);

% -------------------------------------------------------------------------
% Final estimation with the complete DATA array
% -------------------------------------------------------------------------
finalEst = buildEstimator(DATA, METHOD, LEVEL_RANGE, GUESS_RATE, TRUE_SLOPE, TRUE_LAPSE);

estThreshold = [];
finalCI      = [];
finalCIWidth = [];
fitted       = [];

switch upper(METHOD)
    case 'MLP'
        estThreshold = finalEst.Results.AlphaEstimate;
        estSlope     = finalEst.Results.BetaEstimate;
        estLapse     = finalEst.Results.LapseEstimate;
        fitted       = finalEst.Results.FittedPsychFn;

        fprintf('\n--- MLP Final Estimates ---\n');
        fprintf('  Threshold (alpha): estimated = %6.3f  |  true = %6.3f  |  error = %+.3f\n', ...
            estThreshold, TRUE_THRESHOLD, estThreshold - TRUE_THRESHOLD);
        fprintf('  Slope (beta)     : estimated = %6.3f  |  true = %6.3f\n', estSlope, TRUE_SLOPE);
        fprintf('  Lapse (lambda)   : estimated = %6.3f  |  true = %6.3f\n', estLapse, TRUE_LAPSE);

    case 'BESTPEST'
        estThreshold = finalEst.Results.ThresholdEstimate;
        finalCI      = finalEst.Results.ConfidenceInterval;
        finalCIWidth = finalEst.Results.ConfidenceIntervalWidth;

        fprintf('\n--- BestPEST Final Estimates ---\n');
        fprintf('  Threshold       : estimated = %6.3f  |  true = %6.3f  |  error = %+.3f\n', ...
            estThreshold, TRUE_THRESHOLD, estThreshold - TRUE_THRESHOLD);
        fprintf('  95%% CI          : [%.3f, %.3f]  (width = %.3f)\n', ...
            finalCI(1), finalCI(2), finalCIWidth);
end
fprintf('  Trials completed: %d\n', numel(DATA));

% -------------------------------------------------------------------------
% Plots
% -------------------------------------------------------------------------
xPlot = linspace(LEVEL_RANGE(1), LEVEL_RANGE(2), 500);
pTrue = truePsychFn(xPlot);

figure('Name', sprintf('%s Simulation', METHOD), 'NumberTitle', 'off', ...
    'Position', [80 80 1300 480]);
tl = tiledlayout(1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

% ---- Panel 1: Stimulus level history --------------------------------
nexttile;
hitIdx  = find( responseHistory);
missIdx = find(~responseHistory);

plot(hitIdx,  levelHistory(hitIdx),  'go', ...
    'MarkerSize', 6, 'MarkerFaceColor', 'g', 'DisplayName', 'Hit');
hold on;
plot(missIdx, levelHistory(missIdx), 'rx', ...
    'MarkerSize', 8, 'LineWidth', 1.5, 'DisplayName', 'Miss');
yline(TRUE_THRESHOLD, 'b--', 'LineWidth', 1.5, 'DisplayName', 'True threshold');
if ~isempty(estThreshold)
    yline(estThreshold, 'k-', 'LineWidth', 1.5, 'DisplayName', 'Est. threshold');
end
xlabel('Trial');
ylabel('Stimulus Level');
title('Stimulus History');
legend('Location', 'best');
ylim(LEVEL_RANGE + [-2 2]);
grid on;

% ---- Panel 2: Psychometric function ---------------------------------
nexttile;
plot(xPlot, pTrue, 'b-', 'LineWidth', 2, 'DisplayName', 'True PF');
hold on;

switch upper(METHOD)
    case 'MLP'
        if ~isempty(fitted) && isfield(fitted, 'x')
            plot(fitted.x, fitted.P, 'k--', 'LineWidth', 2, 'DisplayName', 'Fitted PF (MLP)');
        end
        sweetPts = finalEst.Results.SweetPoints;
        if ~isempty(sweetPts)
            for k = 1:numel(sweetPts)
                xline(sweetPts(k), ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 1);
            end
            xline(sweetPts(1), ':', 'Color', [0.6 0.6 0.6], 'LineWidth', 1, ...
                'DisplayName', 'Sweet points');
        end

    case 'BESTPEST'
        pFit = GUESS_RATE + (1 - GUESS_RATE - TRUE_LAPSE) ./ ...
            (1 + exp(-TRUE_SLOPE .* (xPlot - estThreshold)));
        plot(xPlot, pFit, 'k--', 'LineWidth', 2, 'DisplayName', 'Fitted PF (BestPEST)');
        if ~isempty(finalCI) && all(isfinite(finalCI))
            xregion(finalCI(1), finalCI(2), ...
                'FaceColor', [0.7 0.7 0.7], 'FaceAlpha', 0.35, ...
                'DisplayName', sprintf('95%% CI (%.1f)', finalCIWidth));
        end
end

xline(TRUE_THRESHOLD, 'b:', 'LineWidth', 1.2, 'DisplayName', 'True \theta');
if ~isempty(estThreshold)
    xline(estThreshold, 'k:', 'LineWidth', 1.2, 'DisplayName', 'Est. \theta');
end

% Binned empirical proportions (require >= 2 trials per bin)
binEdges   = linspace(LEVEL_RANGE(1), LEVEL_RANGE(2), 13);
binCenters = (binEdges(1:end-1) + binEdges(2:end)) / 2;
pHat       = nan(1, numel(binCenters));
for iBin = 1:numel(binCenters)
    inBin = levelHistory >= binEdges(iBin) & levelHistory < binEdges(iBin+1);
    if sum(inBin) >= 2
        pHat(iBin) = mean(responseHistory(inBin));
    end
end
validBins = ~isnan(pHat);
if any(validBins)
    plot(binCenters(validBins), pHat(validBins), 'ks', ...
        'MarkerSize', 8, 'MarkerFaceColor', [0.5 0.5 0.5], ...
        'DisplayName', 'Observed proportion');
end

xlabel('Stimulus Level');
ylabel('P(response)');
title('Psychometric Function');
legend('Location', 'best');
ylim([0 1]);
grid on;

% ---- Panel 3: Convergence -------------------------------------------
nexttile;
validEst = ~isnan(estHistory);
if any(validEst)
    plot(find(validEst), estHistory(validEst), 'k-', 'LineWidth', 1.5, ...
        'DisplayName', 'Threshold estimate');
end
hold on;
yline(TRUE_THRESHOLD, 'b--', 'LineWidth', 1.5, 'DisplayName', 'True threshold');

if strcmpi(METHOD, 'BESTPEST')
    % Shade the running CI as a filled band
    validCI = all(isfinite(ciHistory), 2);
    if any(validCI)
        idx = find(validCI);
        fill([idx; flipud(idx)], ...
            [ciHistory(idx, 1); flipud(ciHistory(idx, 2))], ...
            [0.7 0.7 0.9], 'FaceAlpha', 0.4, 'EdgeColor', 'none', ...
            'DisplayName', '95% CI band');
    end
end

xlabel('Trial');
ylabel('Threshold Estimate');
switch upper(METHOD)
    case 'MLP',      title('MLP \alpha Convergence');
    case 'BESTPEST', title('BestPEST \theta Convergence');
end
legend('Location', 'best');
grid on;

sgtitle(tl, sprintf('%s  |  True \\theta = %.1f  |  n = %d trials', ...
    METHOD, TRUE_THRESHOLD, numel(DATA)));
