function begin_variant_cycle_(obj)
% begin_variant_cycle_(obj)
% Refresh the variant combination cache, select and lock the active variant
% index for this update cycle, and increment its use count.

obj.refresh_variant_cache_if_needed_();
obj.variantCycleActive_ = true;
if isempty(obj.variantCombinationTable_)
    obj.variantActiveIdx_ = 1;
    return
end
obj.variantActiveIdx_ = obj.select_variant_index_();
if numel(obj.variantUseCount_) >= obj.variantActiveIdx_
    obj.variantUseCount_(obj.variantActiveIdx_) = obj.variantUseCount_(obj.variantActiveIdx_) + 1;
end
