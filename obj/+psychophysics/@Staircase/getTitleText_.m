function [titleText, hasTitle] = getTitleText_(obj)
% [titleText, hasTitle] = getTitleText_(obj)
% Build the plot title from the staircase's identity and its results.
%
% The identity is obj.Subject / obj.BoxID when set, else what the runtime's
% TRIALS carries. An offline staircase has no runtime, which is what the two
% properties exist for.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%
% Returns:
%   titleText — char title text (empty when hasTitle=false)
%   hasTitle — logical scalar

titleParts = {};

subjectName = obj.Subject;
boxID = obj.BoxID;
if strlength(subjectName) == 0 || isempty(boxID)
    [rtSubject, rtBox] = localRuntimeIdentity(obj.RUNTIME);
    if strlength(subjectName) == 0, subjectName = rtSubject; end
    if isempty(boxID), boxID = rtBox; end
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
% and the flag can be set before the recompute it triggers has run.
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
end

function [subjectName, boxID] = localRuntimeIdentity(RUNTIME)
% Subject name and box from RUNTIME.TRIALS, or "" and [] when there is no
% runtime, the session has not started, or TRIALS holds several subjects
% (this staircase cannot tell which is its own; the caller sets Subject).
subjectName = "";
boxID = [];
if isempty(RUNTIME) || ~isprop(RUNTIME, 'TRIALS') || isempty(RUNTIME.TRIALS)
    return
end
trials = RUNTIME.TRIALS;
if ~isscalar(trials)
    return
end
S = trials.Subject;   % epsych.Subject, or a struct in a stub runtime
if ~isempty(S)
    subjectName = string(S.Name);
end
boxID = trials.BoxID;
end
