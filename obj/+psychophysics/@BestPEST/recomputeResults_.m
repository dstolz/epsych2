function recomputeResults_(obj)
% recomputeResults_(obj)
% Recompute the maximum likelihood threshold estimate from the active trial
% window. Applies the reset watermark, filters trials by StimulusTrialType,
% extracts stimulus levels and binary responses, and runs the MLE grid search.
% Sets Results to the empty state (NextLevel = max(Range)) when no active
% trials are available after filtering.

results = obj.emptyResults_();

% Apply reset watermark: only consider trials added after the last reset
nTotal = numel(obj.DATA);
if nTotal <= obj.resetCount_
    obj.Results = results;
    return
end
activeData = obj.DATA(obj.resetCount_+1 : end);

% Determine stimulus-trial mask for activeData
if isfield(activeData, 'TrialType')
    ttValues       = reshape(double([activeData.TrialType]), 1, []);
    stimTrialValue = obj.bitMaskToTrialTypeValue_(obj.StimulusTrialType);
    stimMask       = ttValues == stimTrialValue;
else
    % Fall back to response-code bit decoding
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

% Extract stimulus levels, unwrapping Value containers when present
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

% Decode binary responses: positive response = 1, all others = 0
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

% Grid-based MLE
[logL, thetaGrid, slopeGrid, ci] = obj.computeLogLikelihood_(stimLevels, responses);
results.Grid                    = thetaGrid;
results.LogLikelihood           = logL;
results.ConfidenceInterval      = ci;
results.ConfidenceIntervalWidth = diff(ci);

% Extract ML threshold (and slope) estimate
[~, idx] = max(logL(:));
if obj.EstimateSlope
    [rowIdx, colIdx]          = ind2sub(size(logL), idx);
    results.ThresholdEstimate = thetaGrid(rowIdx, colIdx);
    results.SlopeEstimate     = slopeGrid(rowIdx, colIdx);
    effectiveSlope            = results.SlopeEstimate;
else
    results.ThresholdEstimate = thetaGrid(idx);
    results.SlopeEstimate     = [];
    effectiveSlope            = obj.Slope;
end

% NextLevel: optimal sampling point = ML threshold estimate, clamped to Range
results.NextLevel = min(max(results.ThresholdEstimate, obj.Range(1)), obj.Range(2));

% ThresholdAtTarget: analytically inverted stimulus level at TargetProbability
results.ThresholdAtTarget = obj.invertPsychFn_( ...
    obj.TargetProbability, results.ThresholdEstimate, effectiveSlope);

obj.Results = results;
