function T = weightedThreshold(obj, options)
% T = S.weightedThreshold()
% T = S.weightedThreshold(StepFieldYes='Depth_StepOnHit', StepFieldNo='Depth_StepOnMiss')
% T = S.weightedThreshold(StepAfterYes=-2, StepAfterNo=6, ExpectedTarget=0.75)
% Threshold of a weighted (asymmetric-step) staircase, from this session.
%
% Results.Threshold is the plain mean of the last N reversals. For a
% weighted staircase -- one whose step after a "yes" differs in size from
% its step after a "no" (Kaernbach 1991) -- that mean is biased toward the
% tail of the psychometric function, and taken over an unbalanced set of
% reversals it is biased again. This returns Hoover's (2025) corrected
% threshold: the mean of an EQUAL number of ascending and descending
% reversals, plus (delta_- - delta_+)/4. The arithmetic is
% psychophysics.Staircase.correctedReversalMean; this method only turns the
% session into its inputs.
%
% THE STEPS come from one of three places, per side, in this order:
%   1. Stated -- StepAfterYes / StepAfterNo, signed, in the parameter's
%      units. NaN means "find it".
%   2. A DATA field -- StepFieldYes / StepFieldNo name a per-trial field
%      holding the step, as cl_AppetitiveStimDetect records Depth_StepOnHit
%      and Depth_StepOnMiss. Exact where inference is an estimate, and the
%      only way to see an operator editing the step mid-session. Never
%      guessed: a guessed field name silently reads the wrong column.
%   3. Inferred from the track -- the change in level leaving each stimulus
%      trial, attributed to that trial's response. The nominal step is the
%      most common NON-ZERO value, so a step clamped at a parameter bound
%      cannot drag it as a mean would.
% Sources 2 and 3 look only at the steps that produced the reversals used,
% from the step into the first to the step out of the last, so a track that
% runs coarse steps and then fine ones reports the fine ones.
%
% "Yes" is Hit (without Miss) and "no" is Miss (without Hit) on the
% staircase's stimulus trials, as fitPsychometric scores them; an abort is
% neither and so moves nothing. Ascending/descending are read in the
% parameter's own units whatever StaircaseDirection is: the reversals are
% balanced, and the signed steps make the correction the same whichever way
% the parameter runs, so no direction needs to be known.
%
% Steps that are NOT all the same are reported, not refused: T.StepConsistency
% gives the fraction of samples at the nominal step, T.StepsConsistent is
% false, and T.Message names the values seen. A zero step counts against
% consistency -- a transformed (n-down) rule produces them after a yes, and
% the correction is for a 1-up-1-down weighted staircase.
%
% Nothing is stored unless ApplyWeightedCorrection is on, in which case
% recomputeResults_ makes this same call and Results.Weighted holds it.
%
% Parameters:
%   StepAfterYes, StepAfterNo - Stated steps, signed (default: the
%       WeightedStepAfterYes / WeightedStepAfterNo properties, NaN = find).
%   StepFieldYes, StepFieldNo - DATA fields holding the steps (default: the
%       WeightedStepFieldYes / WeightedStepFieldNo properties, "" = none).
%   NumReversals    - Start from the last N reversals, then balance
%                     (default ThresholdFromLastNReversals).
%   LastReversal    - Treat the session as ending at this reversal (default
%                     Inf, the latest). How the sliding-block thresholds
%                     are corrected one block at a time: block k is
%                     NumReversals=N, LastReversal=k+N-1, and its steps are
%                     read from behind ITS reversals, so a coarse-then-fine
%                     track corrects each block by the steps it ran.
%   StepTolerance   - Absolute distance within which two step samples are
%                     the same step. Default NaN: one millionth of the
%                     largest step seen, which absorbs the float drift of
%                     levels read back from single-precision hardware.
%   ExpectedTarget  - The probability the steps were meant to target, as an
%                     assertion (see correctedReversalMean). Default NaN.
%   TargetTolerance - Default 0.01.
%
% Returns:
%   T - Result struct (see emptyWeightedThreshold_), with StepSource,
%       StepConsistency, NumStepsYes/No, ReversalIdx and ParameterName
%       filled in here. Check T.Valid before reading T.Threshold.
%
% Example:
%   S = psychophysics.Staircase(DATA, 'Depth');
%   T = S.weightedThreshold(StepFieldYes='Depth_StepOnHit', StepFieldNo='Depth_StepOnMiss');
%   fprintf('corrected %.2f dB (reversal mean %.2f), targets p = %.3f\n', ...
%       T.Threshold, T.ReversalMean, T.TargetProbability);
%
% See also psychophysics.Staircase.correctedReversalMean,
% documentation/psychophysics/psychophysics_WeightedStaircase.md

arguments
    obj
    options.StepAfterYes (1,1) double = obj.WeightedStepAfterYes
    options.StepAfterNo (1,1) double = obj.WeightedStepAfterNo
    options.StepFieldYes (1,1) string = obj.WeightedStepFieldYes
    options.StepFieldNo (1,1) string = obj.WeightedStepFieldNo
    options.NumReversals (1,1) double {mustBeCountOrInf} = obj.ThresholdFromLastNReversals
    options.LastReversal (1,1) double {mustBeCountOrInf} = Inf
    options.StepTolerance (1,1) double {mustBeNonnegativeOrNaN} = NaN
    options.ExpectedTarget (1,1) double {mustBeProbabilityOrNaN} = NaN
    options.TargetTolerance (1,1) double {mustBeNonnegative} = 0.01
end

T = psychophysics.Staircase.emptyWeightedThreshold_();
T.ParameterName  = obj.ParameterName;
T.ExpectedTarget = options.ExpectedTarget;

if isempty(obj.DATA)
    T.Message = "The staircase holds no trials.";
    return
end

s = obj.sessionVectors_();
R = obj.Results;

if numel(s.stimValues) ~= numel(s.stimMask)
    T.Message = "The tracked parameter has no value on every trial, so levels and responses cannot be paired.";
    return
end

% Too little to track at all: say which, rather than the "no reversals"
% that follows from either.
if isempty(R.StimulusTrialIdx)
    T.Message = sprintf(['No trial is a stimulus trial (StimulusTrialType %s, after ' ...
        'ExcludedTrials), so there is no track.'], char(obj.StimulusTrialType));
    return
end
if ~any(isfinite(s.stimValues(R.StimulusTrialIdx)))
    T.Message = sprintf('No stimulus trial recorded a level for %s, so there is no track.', ...
        char(obj.ParameterName));
    return
end

% ---- The reversals, classified in the parameter's own units --------------
% ReversalDirection is the direction of the step LEAVING the extremum, with
% StaircaseDirection's plotting flip applied; undo the flip, and a peak is
% an extremum left going down.
revIdx = reshape(R.ReversalIdx, 1, []);
rawDir = reshape(R.ReversalDirection, 1, []);
if isfinite(options.LastReversal)
    keep = 1:min(numel(revIdx), options.LastReversal);
    revIdx = revIdx(keep);
    rawDir = rawDir(keep);
end
if obj.StaircaseDirection == "Up"
    rawDir = -rawDir;
end
isAscending = rawDir < 0;
revValues   = s.stimValues(revIdx);

% The same selection correctedReversalMean will make, needed first because
% it decides which steps are read.
[used, why] = psychophysics.Staircase.selectBalancedReversals_(isAscending, ...
    isfinite(revValues), options.NumReversals);

% ---- The steps -------------------------------------------------------------
stated     = [options.StepAfterYes options.StepAfterNo];
fields     = [options.StepFieldYes options.StepFieldNo];
sideName   = ["yes" "no"];
stepOpt    = ["StepAfterYes" "StepAfterNo"];
fieldOpt   = ["StepFieldYes" "StepFieldNo"];

% The stimulus trials the reversals were found among, not a fresh mask: a
% StimulusTrialType changed without refresh_history() would otherwise pair
% these reversals with a different set of trials.
stimIdx = reshape(R.StimulusTrialIdx, 1, []);
[win, winMsg] = stepWindow_(s.stimValues(stimIdx), stimIdx, revIdx, used, why);

% Hit and Miss both on one code say two things about one trial; that trial
% moves neither step, as fitPsychometric leaves it unscored.
codesOk = ~isempty(s.decoded) && numel(s.decoded.Hit) == obj.trialCount;
if codesOk
    respMask = [reshape(s.decoded.Hit & ~s.decoded.Miss, 1, []); ...
                reshape(s.decoded.Miss & ~s.decoded.Hit, 1, [])];
end

step    = [NaN NaN];
source  = ["" ""];
counts  = [0 0];
reasons = strings(1,0);
notes   = strings(1,0);
uninferable = zeros(1,0);     % sides needing inference from codes DATA lacks

for k = 1:2
    if isfinite(stated(k))
        step(k)   = stated(k);
        source(k) = "stated";
        continue
    end

    if strlength(winMsg) > 0
        reasons(end+1) = winMsg;
        continue
    end

    if codesOk, rm = respMask(k,:); else, rm = []; end

    if strlength(fields(k)) > 0
        source(k) = "field";
        if isfield(obj.DATA, char(fields(k)))
            values = obj.dataFieldValues_(char(fields(k)));
        else
            values = [];
        end
        [samples, msg] = fieldSamples_(values, fields(k), fieldOpt(k), ...
            isfield(obj.DATA, char(fields(k))), obj.trialCount, stimIdx(win), rm);
    elseif ~codesOk
        uninferable(end+1) = k;
        continue
    else
        source(k) = "inferred";
        [samples, msg] = trackSamples_(s.stimValues(stimIdx), stimIdx, win, rm, sideName(k));
    end

    if strlength(msg) > 0
        reasons(end+1) = msg;
        continue
    end

    [step(k), T.StepConsistency(k), note] = nominalStep_(samples, options.StepTolerance, sideName(k));
    counts(k) = numel(samples);
    if strlength(note) > 0
        notes(end+1) = note;
    end
end

if ~isempty(uninferable)
    reasons(end+1) = sprintf(['DATA carries no response code on every trial, so the step after a %s ' ...
        'cannot be inferred; state %s or name %s.'], strjoin(sideName(uninferable), ' and after a '), ...
        strjoin(stepOpt(uninferable), '/'), strjoin(fieldOpt(uninferable), '/'));
end

% ---- The estimate ----------------------------------------------------------
W = psychophysics.Staircase.correctedReversalMean(revValues, isAscending, step(1), step(2), ...
    NumReversals    = options.NumReversals, ...
    ExpectedTarget  = options.ExpectedTarget, ...
    TargetTolerance = options.TargetTolerance);

measured = T.StepConsistency(~isnan(T.StepConsistency));
W.StepSource      = joinSource_(source);
W.StepConsistency = T.StepConsistency;
W.StepsConsistent = all(measured == 1);
W.NumStepsYes     = counts(1);
W.NumStepsNo      = counts(2);
W.ReversalIdx     = revIdx;
W.ParameterName   = T.ParameterName;

if ~isempty(reasons)
    % The estimator's own message would only restate an undetermined (NaN)
    % step or the reversal problem the window already named.
    W.Valid     = false;
    W.Threshold = NaN;
    W.Message   = strjoin(unique(reasons, 'stable'), " ");
    T = W;
    return
end

if obj.ThresholdFormula == "GeometricMean"
    notes(end+1) = "ThresholdFormula is GeometricMean, but the correction is additive in " + ...
        "the parameter's own units, so this threshold uses the arithmetic mean of the reversals.";
end

parts = [W.Message notes];
W.Message = strjoin(parts(strlength(parts) > 0), " ");
T = W;
end

% =========================================================================
function [win, msg] = stepWindow_(lv, stimIdx, revIdx, used, why)
% Positions, among the stimulus trials, of the steps that produced the
% reversals used: from the step into the first to the step out of the last.
% The step at position p leaves stimulus trial p for stimulus trial p + 1.
% With no balanced pair there are no such steps, and why says so.
win = zeros(1,0);
msg = why;
if strlength(msg) > 0
    return
end

d = diff(lv);
firstPos = find(stimIdx == revIdx(find(used, 1, 'first')), 1);
lastPos  = find(stimIdx == revIdx(find(used, 1, 'last')), 1);
if isempty(firstPos) || isempty(lastPos)
    % Unreachable while Results is current; say so rather than read nothing.
    msg = "The staircase's results are out of date with its trials; call refresh_history().";
    return
end

% Holds (zero steps) can sit between an extremum and the step that leaves
% it; the step out is the first real step at or after the extremum.
outPos = lastPos - 1 + find(isfinite(d(lastPos:end)) & d(lastPos:end) ~= 0, 1);
if isempty(outPos), outPos = numel(d); end

win = max(1, firstPos - 1):outPos;
end

% =========================================================================
function [samples, msg] = trackSamples_(lv, stimIdx, win, respMask, sideName)
% The change in level leaving each stimulus trial in the window that drew
% this response. A step into or out of a NaN level is dropped, never read
% as zero.
d = diff(lv);
sel = win(respMask(stimIdx(win)));
samples = d(sel);
samples = samples(isfinite(samples));

msg = "";
if isempty(samples)
    msg = sprintf('No step after a %s falls within the reversals used, so it cannot be inferred.', sideName);
end
end

% =========================================================================
function [samples, msg] = fieldSamples_(values, fieldName, optionName, present, nTrials, trials, respMask)
% The field's value on each stimulus trial in the window that drew this
% response: the step in force when that response moved the track (a
% paradigm's parameters are read at trial completion, before the next trial
% is selected). Without response codes every stimulus trial in the window
% is read instead -- the field is a setting, not an outcome.
samples = [];
msg = "";

if ~present
    msg = sprintf('DATA has no field ''%s'' (%s).', fieldName, optionName);
    return
end
if ~(isnumeric(values) || islogical(values)) || numel(values) ~= nTrials
    msg = sprintf('DATA field ''%s'' (%s) does not hold one number per trial.', fieldName, optionName);
    return
end

if ~isempty(respMask)
    trials = trials(respMask(trials));
end

samples = double(values(trials));
samples = samples(isfinite(samples));
if isempty(samples)
    msg = sprintf('DATA field ''%s'' (%s) has no defined value where it applied within the reversals used.', ...
        fieldName, optionName);
end
end

% =========================================================================
function [nominal, frac, note] = nominalStep_(samples, tol, sideName)
% The most common non-zero step, the fraction of ALL samples at it, and a
% note naming what was seen when that fraction is not 1.
note = "";
samples = reshape(samples, 1, []);

if isnan(tol)
    tol = 1e-6 * max(abs(samples));
end
if tol > 0
    % DataScale 1 makes the tolerance absolute; uniquetol's default scales
    % it by the largest value, which is not what a stated tolerance means.
    [~, ~, ic] = uniquetol(samples, tol, 'DataScale', 1);
else
    [~, ~, ic] = unique(samples);
end
ic = ic(:);

groupVal  = accumarray(ic, samples(:), [], @mean)';
groupN    = accumarray(ic, 1)';
groupLast = accumarray(ic, (1:numel(samples))', [], @max)';

isZero = abs(groupVal) <= tol;
candidates = find(~isZero);
if isempty(candidates)
    nominal = 0;          % correctedReversalMean refuses a zero step
    frac = 1;
    return
end

% Ties go to the value in force most recently.
best = candidates(groupN(candidates) == max(groupN(candidates)));
[~, k] = max(groupLast(best));
g = best(k);

nominal = groupVal(g);
frac = groupN(g) / numel(samples);

if frac < 1
    [~, order] = sort(groupN, 'descend');
    parts = arrayfun(@(j) sprintf('%g (%.0f%%)', groupVal(j), 100*groupN(j)/numel(samples)), ...
        order, 'UniformOutput', false);
    note = sprintf('The steps after a %s were not all the same: %s of %d; the correction uses %g.', ...
        sideName, strjoin(parts, ', '), numel(samples), nominal);
    if any(isZero)
        note = sprintf(['%s A zero step after a %s is what a clamp at a parameter bound, or a ' ...
            'transformed (n-down) rule, produces; the correction is for a 1-up-1-down weighted staircase.'], ...
            note, sideName);
    end
    note = string(note);
end
end

% =========================================================================
function src = joinSource_(source)
% One word when both steps came from the same place, "<yes>/<no>" otherwise.
if source(1) == source(2)
    src = source(1);
else
    src = source(1) + "/" + source(2);
end
end

% =========================================================================
function mustBeCountOrInf(x)
if ~(x > 0 && (isinf(x) || x == fix(x)))
    error('psychophysics:Staircase:InvalidNumReversals', ...
        'NumReversals and LastReversal must be a positive integer or Inf.');
end
end

% =========================================================================
function mustBeNonnegativeOrNaN(x)
if ~(isnan(x) || x >= 0)
    error('psychophysics:Staircase:InvalidStepTolerance', ...
        'StepTolerance must be NaN or nonnegative.');
end
end

% =========================================================================
function mustBeProbabilityOrNaN(x)
if ~(isnan(x) || (x > 0 && x < 1))
    error('psychophysics:Staircase:InvalidExpectedTarget', ...
        'ExpectedTarget must be NaN or a probability strictly between 0 and 1.');
end
end
