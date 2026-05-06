function [comboTable, comboProps] = build_variant_combinations_(obj, propNames, propValues)
% [comboTable, comboProps] = build_variant_combinations_(obj, propNames, propValues)
% Build the variant combination table according to VariantCombinationMode.
%
% Parameters:
%   propNames  - 1-by-N string array of vectorized property names.
%   propValues - 1-by-N cell array of corresponding row vectors.
%
% Returns:
%   comboTable - 1-by-M struct array; each element maps propName to a scalar.
%   comboProps - Property names included in the combinations.

comboProps = propNames;
if isempty(propNames)
    comboTable = struct.empty(1,0);
    return
end

nProps = numel(propNames);
mode = obj.VariantCombinationMode;
switch mode
    case "Cartesian"
        grids = cell(1, nProps);
        [grids{:}] = ndgrid(propValues{:});
        nComb = numel(grids{1});
        fieldNames = cellstr(propNames);
        fieldValues = repmat({[]}, 1, nProps);
        seed = cell2struct(fieldValues, fieldNames, 2);
        comboTable = repmat(seed, 1, nComb);
        for i = 1:nComb
            for p = 1:nProps
                comboTable(i).(fieldNames{p}) = grids{p}(i);
            end
        end
    otherwise
        lengths = cellfun(@numel, propValues);
        maxLen = max(lengths);
        switch mode
            case "PairwiseStrict"
                if any(lengths ~= maxLen)
                    error('stimgen:StimType:PairwiseLengthMismatch', ...
                        'PairwiseStrict requires equal vector lengths for all vectorized properties.');
                end
                expanded = propValues;
            case "PairwiseScalarExpand"
                valid = (lengths == 1) | (lengths == maxLen);
                if ~all(valid)
                    error('stimgen:StimType:PairwiseLengthMismatch', ...
                        'PairwiseScalarExpand requires each vector length to be either 1 or the shared max length.');
                end
                expanded = propValues;
                for p = 1:nProps
                    if numel(expanded{p}) == 1
                        expanded{p} = repmat(expanded{p}, 1, maxLen);
                    end
                end
            otherwise
                error('stimgen:StimType:InvalidCombinationMode', ...
                    'Unknown VariantCombinationMode "%s".', char(mode));
        end

        fieldNames = cellstr(propNames);
        fieldValues = repmat({[]}, 1, nProps);
        seed = cell2struct(fieldValues, fieldNames, 2);
        comboTable = repmat(seed, 1, maxLen);
        for i = 1:maxLen
            for p = 1:nProps
                comboTable(i).(fieldNames{p}) = expanded{p}(i);
            end
        end
end
