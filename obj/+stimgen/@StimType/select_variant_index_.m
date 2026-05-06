function idx = select_variant_index_(obj)
% idx = select_variant_index_(obj)
% Choose the next variant index according to VariantSelectionMode.
% Returns 1 when there is only one combination.
%
% Returns:
%   idx - 1-based index into variantCombinationTable_.

nComb = numel(obj.variantCombinationTable_);
if nComb <= 1
    idx = 1;
    return
end

switch obj.VariantSelectionMode
    case "Serial"
        idx = obj.variantCurrentIdx_;
        idx = min(max(idx,1), nComb);
        obj.variantCurrentIdx_ = mod(idx, nComb) + 1;
    case "ShuffleUniform"
        idx = randi(nComb);
        obj.variantCurrentIdx_ = idx;
    case "ShuffleLeastUsed"
        counts = obj.variantUseCount_;
        if isempty(counts) || numel(counts) ~= nComb
            counts = zeros(1, nComb);
            obj.variantUseCount_ = counts;
        end
        minCount = min(counts);
        candidates = find(counts == minCount);
        idx = candidates(randi(numel(candidates)));
        obj.variantCurrentIdx_ = idx;
    case "CustomSelector"
        selector = obj.get_or_create_variant_selector_();
        trialRows = num2cell((1:nComb).');
        trialsStruct = struct('trials', {trialRows});
        idx = selector.selectNext(trialsStruct);
        if ~isscalar(idx) || ~isfinite(idx) || idx < 1 || idx > nComb
            error('stimgen:StimType:InvalidSelectorIndex', ...
                'Custom selector returned invalid index for %d variants.', nComb);
        end
        idx = double(idx);
        obj.variantCurrentIdx_ = idx;
    otherwise
        error('stimgen:StimType:InvalidSelectionMode', ...
            'Unknown VariantSelectionMode "%s".', char(obj.VariantSelectionMode));
end
