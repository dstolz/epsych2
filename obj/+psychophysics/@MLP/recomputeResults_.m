function recomputeResults_(obj)
% recomputeResults_(obj)
% Recompute all MLP outputs from the active trial window. Applies the reset
% watermark, filters to stimulus trials, extracts signal strengths and binary
% responses, then: computes the 3D Bayesian posterior, extracts ML parameter
% estimates, numerically finds sweet points, selects the next stimulus level,
% and populates all Results fields. Returns to the empty state when no active
% stimulus trials are available.

results = obj.emptyResults_();

% Apply reset watermark: only trials added after the last reset are used
nTotal = numel(obj.DATA);
if nTotal <= obj.resetCount_
    obj.Results = results;
    return
end
activeData = obj.DATA(obj.resetCount_+1 : end);

% Determine which activeData entries are stimulus trials
if isfield(activeData, 'TrialType')
    ttValues       = reshape(double([activeData.TrialType]), 1, []);
    stimTrialValue = obj.bitMaskToTrialTypeValue_(obj.StimulusTrialType);
    stimMask       = ttValues == stimTrialValue;
else
    rcField = obj.resolveRespCodeField_(activeData);
    if isempty(rcField)
        obj.Results = results;
        return
    end
    rc       = uint32([activeData.(rcField)]);
    decoded  = epsych.BitMask.decode(rc);
    stimMask = logical(decoded.(char(obj.StimulusTrialType)));
end

stimMask = reshape(logical(stimMask), 1, []);
stimData = activeData(stimMask);

if isempty(stimData)
    obj.Results = results;
    return
end

% Extract stimulus signal strengths, unwrapping hw.Parameter Value containers
fieldName = obj.parameterFieldName_();
if ~isfield(stimData, fieldName)
    obj.Results = results;
    return
end
rawVals = [stimData.(fieldName)];
sample  = rawVals(1);
if (isstruct(sample) && isfield(sample, 'Value')) || ...
   (isobject(sample) && isprop(sample, 'Value'))
    stimLevels = double([rawVals.Value]);
else
    stimLevels = double(rawVals);
end
stimLevels = reshape(stimLevels, 1, []);

% Decode binary responses: positive (correct) response = 1, all others = 0
rcField = obj.resolveRespCodeField_(stimData);
if isempty(rcField)
    obj.Results = results;
    return
end
rc          = uint32([stimData.(rcField)]);
decodedResp = epsych.BitMask.decode(rc);
responses   = double(logical(decodedResp.(char(obj.PositiveResponseBit))));
responses   = reshape(responses, 1, []);

results.TrialCount     = numel(stimLevels);
results.StimulusLevels = stimLevels;
results.Responses      = responses;

% 3D Bayesian log-posterior: (nAlpha x nBeta x nLapse)
[logPosterior, alphaVec, betaVec, lapseVec] = obj.computePosterior_(stimLevels, responses);

% Normalize to probability for Results output
logPost   = logPosterior - max(logPosterior(:));
posterior = exp(logPost);
posterior = posterior / sum(posterior(:));
results.Posterior = posterior;

% ML parameter estimates: argmax of logPosterior
[~, iMax] = max(logPosterior(:));
[iA, iB, iL] = ind2sub(size(logPosterior), iMax);
alphaML = alphaVec(iA);
betaML  = betaVec(iB);
lapseML = lapseVec(iL);

results.AlphaEstimate = alphaML;
results.BetaEstimate  = betaML;
results.LapseEstimate = lapseML;

% Sweet points from ML parameter estimates
sweetPoints = obj.computeSweetPoints_(alphaML, betaML, lapseML);
results.SweetPoints        = sweetPoints;
results.SweetPointPcorrect = obj.evaluatePsychFn_(sweetPoints, alphaML, betaML, lapseML);

% Next stimulus level via the configured sweet-point selection rule
results.NextLevel              = obj.selectNextLevel_(sweetPoints, responses);
results.CurrentSweetPointIndex = obj.sweetPointIdx_;

% Fitted psychometric function over the full signal range for plotting
xFit = linspace(obj.AlphaRange(1), obj.MaxSignalStrength, 200);
results.FittedPsychFn = struct( ...
    'x', xFit, ...
    'P', obj.evaluatePsychFn_(xFit, alphaML, betaML, lapseML));

obj.Results = results;
