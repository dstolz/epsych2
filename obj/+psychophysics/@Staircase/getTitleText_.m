function [titleText, hasTitle] = getTitleText_(obj)
% [titleText, hasTitle] = getTitleText_(obj)
% Build plot title string from runtime + staircase state.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   titleText — char title text (empty when hasTitle=false)
%   hasTitle — logical scalar

titleParts = {};

if ~isempty(obj.RUNTIME) && isprop(obj.RUNTIME,'TRIALS') && ~isempty(obj.RUNTIME.TRIALS)
    trials = obj.RUNTIME.TRIALS;

    subjectName = "";
    if isprop(trials, 'Subject') && ~isempty(trials.Subject) && isprop(trials.Subject, 'Name')
        subjectName = string(trials.Subject.Name);
    end

    boxID = [];
    if isprop(trials, 'BoxID')
        boxID = trials.BoxID;
    end

    if isempty(boxID)
        if strlength(subjectName) > 0
            titleParts{end+1} = char(subjectName);
        end
    elseif strlength(subjectName) == 0
        titleParts{end+1} = sprintf('[%d]', boxID);
    else
        titleParts{end+1} = sprintf('%s [%d]', subjectName, boxID);
    end
end

if ~isempty(obj.Results.ReversalCount)
    reversalCount = obj.Results.ReversalCount;
    if isscalar(reversalCount) && isfinite(reversalCount)
        titleParts{end+1} = sprintf('Reversals: %d', reversalCount);
    end
end

R = obj.Results;
threshold = R.Threshold;
hasThreshold = isscalar(threshold) && isfinite(threshold);
configuredReversals = obj.ThresholdFromLastNReversals;

% Results.Weighted, not the flag: the title describes what Results holds,
% and the flag can be set before refresh_history() has run.
isCorrected = ~isempty(R.Weighted);

if hasThreshold && isCorrected
    % Say the numbers are corrected, and by how much, so a screenshot pasted
    % into a notebook describes itself. The count is the balanced set the
    % correction actually averaged, which can be one short of N.
    W = R.Weighted;
    label = sprintf('Corrected threshold (%d/%d rev, %+.2f)', ...
        W.NumReversals, configuredReversals, W.Correction);
elseif hasThreshold
    actualReversals = R.ReversalCount;
    if isscalar(actualReversals) && isfinite(actualReversals)
        nUsed = min(actualReversals, configuredReversals);
        label = sprintf('Threshold (%d/%d rev)', nUsed, configuredReversals);
    else
        label = sprintf('Threshold (last %d rev)', configuredReversals);
    end
elseif isCorrected && isscalar(R.ReversalCount) && R.ReversalCount > 0
    % Asked for and refused: without this the threshold would simply vanish
    % from the title when the operator ticks the correction. The reason
    % (Results.Weighted.Message) is too long for a title and is logged.
    titleParts{end+1} = 'Corrected threshold: unavailable';
end

if hasThreshold
    % The summary spans every sliding block of N reversals, which exists
    % only once one whole block does; before that only the latest shows.
    blockStats = [R.MinBlockThreshold R.MedianBlockThreshold ...
        R.MeanBlockThreshold R.MaxBlockThreshold];
    if numel(blockStats) == 4 && all(isfinite(blockStats))
        titleParts{end+1} = sprintf('%s latest: %.2f; min %.2f; med: %.2f; mean: %.2f; max: %.2f', ...
            label, threshold, blockStats);
    else
        titleParts{end+1} = sprintf('%s latest: %.2f', label, threshold);
    end
end

hasTitle = ~isempty(titleParts);
if hasTitle
    titleText = strjoin(titleParts, ' | ');
else
    titleText = '';
end
