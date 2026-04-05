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
    if isscalar(threshold) && isfinite(threshold)
        configuredReversals = obj.ThresholdFromLastNReversals;
        actualReversals = obj.Results.ReversalCount;

        if isscalar(configuredReversals) && isfinite(configuredReversals)
            if isscalar(actualReversals) && isfinite(actualReversals)
                nUsed = min(actualReversals, configuredReversals);
                titleParts{end+1} = sprintf('Threshold (%d/%d rev): %.3f', nUsed, configuredReversals, threshold);
            else
                titleParts{end+1} = sprintf('Threshold (last %d rev): %.3f', configuredReversals, threshold);
            end
        else
            titleParts{end+1} = sprintf('Threshold: %.3f', threshold);
        end
    end
end

hasTitle = ~isempty(titleParts);
if hasTitle
    titleText = strjoin(titleParts, ' | ');
else
    titleText = '';
end
