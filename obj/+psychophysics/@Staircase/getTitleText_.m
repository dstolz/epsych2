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

if ~isempty(obj.Results.Threshold)
    threshold = obj.Results.Threshold;
    if isscalar(threshold) && isfinite(threshold) && obj.ApplyWeightedCorrection
        % Say the number is corrected, and by how much, so a screenshot
        % pasted into a notebook describes itself.
        W = obj.Results.Weighted;
        titleParts{end+1} = sprintf('Corrected threshold (%d/%d rev, %+.2f): %.2f', ...
            W.NumReversals, obj.ThresholdFromLastNReversals, W.Correction, threshold);
    elseif isscalar(threshold) && isfinite(threshold)
        configuredReversals = obj.ThresholdFromLastNReversals;
        actualReversals = obj.Results.ReversalCount;

        if isscalar(configuredReversals) && isfinite(configuredReversals)
            if isscalar(actualReversals) && isfinite(actualReversals)
                nUsed = min(actualReversals, configuredReversals);
                titleParts{end+1} = sprintf('Threshold (%d/%d rev): %.2f', nUsed, configuredReversals, threshold);
            else
                titleParts{end+1} = sprintf('Threshold (last %d rev): %.2f', configuredReversals, threshold);
            end
        else
            titleParts{end+1} = sprintf('Threshold: %.2f', threshold);
        end

        minBlock = obj.Results.MinBlockThreshold;
        if isscalar(minBlock) && isfinite(minBlock)
            titleParts{end} = sprintf('%s (min %.2f)', titleParts{end}, minBlock);
        end
    end
end

hasTitle = ~isempty(titleParts);
if hasTitle
    titleText = strjoin(titleParts, ' | ');
else
    titleText = '';
end
