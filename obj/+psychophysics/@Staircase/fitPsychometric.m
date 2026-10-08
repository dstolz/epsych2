function F = fitPsychometric(obj, options)
% F = S.fitPsychometric()
% F = S.fitPsychometric(Shape="Weibull", ThresholdCriterion=0.707)
% F = S.fitPsychometric(Bootstrap=1000, GuessFromCatchTrials=true)
% Fit a psychometric function to the staircase's trials.
%
% A staircase reports a threshold from its reversals; this reports one from
% the responses themselves, together with a slope, the shape of the function,
% and how well it describes the session. The two answer different questions
% and are worth comparing: a reversal mean is a running average of where the
% rule put the stimulus, while the fit uses every scored trial at every level
% the session visited.
%
% The trials are the staircase's own: STIMULUS trials as StimulusTrialType
% selects them, with ExcludedTrials already removed, so the fit is always in
% the units the plot is showing.
% A trial counts as a "yes" when its response code carries Hit, and as a "no"
% when it carries Miss. An aborted trial is left out by default -- an abort is
% a lapse of engagement rather than a wrong answer, the same convention
% psychophysics.Metrics.rateDenominator states for every rate in the toolbox
% -- and IncludeAborts=true counts it as a failure to respond instead.
% Anything else on a stimulus trial, including a code carrying both Hit and
% Miss, is unscored and reported in F.NumUnscored rather than guessed at.
%
% READ THE SLOPE WITH CARE. Levels a staircase visits are chosen in response
% to the subject, so the trials are not an independent sample of the
% psychometric function: a maximum-likelihood fit to adaptive data recovers
% the threshold with little bias but tends to OVERSTATE the slope, by a few
% percent for a long track and more for a short one (Leek, Hanna & Marshall
% 1992; Treutwein & Strasburger 1999; Kaernbach 2001). The bootstrap interval
% resamples at the levels the session ran and does not carry that either.
% A slope worth quoting comes from the method of constant stimuli.
%
% Nothing is stored: the fit is returned, never written onto obj.Results, so
% it can never be a stale number sitting beside live trials. Call it again
% after more data arrive.
%
% Parameters:
%   IncludeAborts        - Count aborted stimulus trials as failures to
%                          respond (default false).
%   GuessFromCatchTrials - Take the lower asymptote gamma from the false
%                          alarm rate on this staircase's CATCH trials
%                          (CatchTrialType) instead of the GuessRate option.
%                          Default false. A session with no scored catch
%                          trial falls back to GuessRate and says so in
%                          F.GuessRateSource.
%   LevelTolerance       - Merge levels within this ABSOLUTE distance of one
%                          another before counting, for a rig whose level
%                          accumulates floating-point drift. Default 0, which
%                          groups exactly equal levels only; the merged
%                          level is the mean of the values it stands for.
%   ...                  - Every psychophysics.Staircase.fitProportions
%                          option is accepted and forwarded unchanged: Shape,
%                          Direction, GuessRate, LapseRate, EstimateLapse,
%                          MaxLapse, ThresholdCriterion, CriterionScale,
%                          StartAlpha, StartBeta, Bootstrap, ConfidenceLevel,
%                          RandomSeed, CurvePoints, MinResponseRange,
%                          MaxIterations.
%
% Returns:
%   F - Fit result struct from fitProportions, plus the fields describing
%       where the counts came from: ParameterName, NumScored,
%       NumAborted, NumUnscored, NumUndefinedLevel and
%       GuessRateSource. Check F.Converged and F.Identifiable before reading
%       F.Threshold; F.Message says what went wrong when either is false.
%
% Example:
%   S = psychophysics.Staircase(DATA, 'Depth');   % Depth in dB re 100%
%   F = S.fitPsychometric(ThresholdCriterion=0.707, CriterionScale="absolute");
%   fprintf('reversal threshold %.2f dB, fitted %.2f dB\n', ...
%       S.Results.Threshold, F.Threshold);
%   plot(F.Curve.x, F.Curve.P); hold on
%   scatter(F.Levels, F.Proportion, 20*F.NumTotal, 'filled');
%
% See also psychophysics.Staircase.fitProportions,
% psychophysics.Staircase.psychometricFunction, psychophysics.BestPEST,
% psychophysics.MLP, documentation/psychophysics/psychophysics_StaircaseFit.md

% The forwarded defaults below MUST match fitProportions' own; MATLAB has no
% way to inherit an arguments block. tmp/smoke_test_staircase_fit.m parses
% both files and fails when they drift apart.
arguments
    obj
    options.IncludeAborts (1,1) logical = false
    options.GuessFromCatchTrials (1,1) logical = false
    options.LevelTolerance (1,1) double {mustBeNonnegative} = 0
    options.Shape (1,1) string {mustBeMember(options.Shape,["Logistic","Normal","Weibull"])} = "Logistic"
    options.Direction (1,1) string {mustBeMember(options.Direction,["increasing","decreasing"])} = "increasing"
    options.GuessRate (1,1) double {mustBeInRange(options.GuessRate,0,1)} = 0
    options.LapseRate (1,1) double {mustBeInRange(options.LapseRate,0,1)} = 0
    options.EstimateLapse (1,1) logical = false
    options.MaxLapse (1,1) double {mustBeInRange(options.MaxLapse,0,1,"exclusive")} = 0.05
    options.ThresholdCriterion (1,1) double {mustBeInRange(options.ThresholdCriterion,0,1,"exclusive")} = 0.5
    options.CriterionScale (1,1) string {mustBeMember(options.CriterionScale,["relative","absolute"])} = "relative"
    options.StartAlpha (1,1) double = NaN
    options.StartBeta (1,1) double = NaN
    options.Bootstrap (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    options.ConfidenceLevel (1,1) double {mustBeInRange(options.ConfidenceLevel,0,1,"exclusive")} = 0.95
    options.RandomSeed = []
    options.CurvePoints (1,1) double {mustBeNonnegative, mustBeInteger} = 200
    options.MinResponseRange (1,1) double {mustBeInRange(options.MinResponseRange,0,1)} = 0.05
    options.MaxIterations (1,1) double {mustBePositive, mustBeInteger} = 2000
end

% The scoring and the per-level counts are psychometricCounts', shared with
% every other fit of these trials (psignifit takes the same data matrix).
C = obj.psychometricCounts(IncludeAborts = options.IncludeAborts, ...
    LevelTolerance = options.LevelTolerance);

extra = struct( ...
    'ParameterName',     C.ParameterName, ...
    'NumScored',         C.NumScored, ...
    'NumAborted',        C.NumAborted, ...
    'NumUnscored',       C.NumUnscored, ...
    'NumUndefinedLevel', C.NumUndefinedLevel, ...
    'GuessRateSource',   "fixed");

if C.Message ~= ""
    F = decorate_(psychophysics.Staircase.emptyFit_(), options, extra);
    F.Message = C.Message;
    return
end

% ---- Lower asymptote from the catch trials -------------------------------
guessRate = options.GuessRate;
if options.GuessFromCatchTrials
    fa = C.CatchFalseAlarmRate;
    if isfinite(fa) && fa < 1 - options.LapseRate
        guessRate = fa;
        extra.GuessRateSource = "catch";
    else
        vprintf(0, 1, ['Psychometric fit: GuessFromCatchTrials found no usable ' ...
            'catch-trial false alarm rate; falling back to GuessRate.']);
        extra.GuessRateSource = "fixed (no usable catch trials)";
    end
end

% ---- Fit -----------------------------------------------------------------
fitOpts = rmfield(options, {'IncludeAborts','GuessFromCatchTrials','LevelTolerance'});
fitOpts.GuessRate = guessRate;

% The reversal threshold is prior information about where the function sits,
% so it joins the optimizer's starting points. It only ever ADDS a start --
% the highest likelihood still wins -- so a staircase with few reversals
% cannot drag the estimate anywhere.
if ~isfinite(fitOpts.StartAlpha) && isscalar(obj.Results.Threshold) && isfinite(obj.Results.Threshold)
    fitOpts.StartAlpha = obj.Results.Threshold;
end

args = namedargs2cell(fitOpts);
F = decorate_(psychophysics.Staircase.fitProportions(C.Levels, C.NumYes, C.NumTotal, args{:}), ...
    options, extra);
end

% =========================================================================
function F = decorate_(F, options, extra)
% Append the session-level fields in one place, so every return path -- the
% refusals included -- hands back a struct with the same fields in the same
% order.
F.Shape     = options.Shape;
F.Direction = options.Direction;

names = fieldnames(extra);
for k = 1:numel(names)
    F.(names{k}) = extra.(names{k});
end
end
