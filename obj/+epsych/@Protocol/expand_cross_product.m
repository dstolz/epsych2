function trials_out = expand_cross_product(obj, trials_in, paramMetadata)
% trials_out = expand_cross_product(obj, trials_in, paramMetadata)
%
% Expand an initial single-row trial specification into a full
% cross-product of all parameter value combinations, respecting paired
% parameter groups.
%
% Parameters:
%   trials_in     - 1-by-N cell array of raw parameter values
%   paramMetadata - 1-by-N cell array of structs with fields:
%                     name - fully qualified parameter name
%                     pair - pair/buddy group name (empty if unpaired)
%
% Returns:
%   trials_out - M-by-N cell array (M = total trial combinations)

if isempty(trials_in)
    trials_out = {};
    return
end

nCols = size(trials_in, 2);
groupKeys = {};
groupColumns = {};
groupValueSets = {};

for col = 1:nCols
    valueSet = obj.normalizeParameterValuesForTrials_(trials_in{1, col});
    pairName = strtrim(char(string(paramMetadata{col}.pair)));
    if isempty(pairName)
        groupKey = sprintf('__solo_%d__', col);
    else
        groupKey = sprintf('pair:%s', pairName);
    end

    groupIdx = find(strcmp(groupKeys, groupKey), 1);
    if isempty(groupIdx)
        groupKeys{end + 1} = groupKey; %#ok<AGROW>
        groupColumns{end + 1} = col; %#ok<AGROW>
        groupValueSets{end + 1} = {valueSet}; %#ok<AGROW>
    else
        groupColumns{groupIdx}(end + 1) = col;
        groupValueSets{groupIdx}{end + 1} = valueSet;
    end
end

groupLengths = ones(1, numel(groupKeys));
for groupIdx = 1:numel(groupKeys)
    valueLengths = cellfun(@numel, groupValueSets{groupIdx});
    if any(valueLengths ~= valueLengths(1))
        error('epsych:Protocol:PairMismatch', ...
            'Pair group "%s" has mismatched value counts.', groupKeys{groupIdx});
    end
    groupLengths(groupIdx) = valueLengths(1);
end

if numel(groupLengths) == 1
    combos = (1:groupLengths(1)).';
else
    gridArgs = cell(1, numel(groupLengths));
    for groupIdx = 1:numel(groupLengths)
        gridArgs{groupIdx} = 1:groupLengths(groupIdx);
    end

    grid = cell(1, numel(groupLengths));
    [grid{:}] = ndgrid(gridArgs{:});
    combos = zeros(numel(grid{1}), numel(groupLengths));
    for groupIdx = 1:numel(groupLengths)
        combos(:, groupIdx) = grid{groupIdx}(:);
    end
end

trials_out = cell(size(combos, 1), nCols);
for comboIdx = 1:size(combos, 1)
    for groupIdx = 1:numel(groupKeys)
        valueIdx = combos(comboIdx, groupIdx);
        groupCols = groupColumns{groupIdx};
        groupValues = groupValueSets{groupIdx};
        for memberIdx = 1:numel(groupCols)
            trials_out{comboIdx, groupCols(memberIdx)} = groupValues{memberIdx}{valueIdx};
        end
    end
end
end
