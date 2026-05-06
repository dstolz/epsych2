function info = apply_variant_index_and_update_(obj, idx)
% info = apply_variant_index_and_update_(obj, idx)
% Lock a specific variant index, regenerate Signal, then release the lock.
% The index wraps cyclically over the number of combinations.
%
% Parameters:
%   idx - Desired 1-based variant index (will be wrapped).
%
% Returns:
%   info - Variant state struct from get_variant_info().

obj.refresh_variant_cache_if_needed_();

nComb = numel(obj.variantCombinationTable_);
if nComb < 1
    nComb = 1;
end

targetIdx = mod(round(double(idx)) - 1, nComb) + 1;

cycleWasActive = obj.variantCycleActive_;
prevActiveIdx = obj.variantActiveIdx_;

obj.variantCycleActive_ = true;
obj.variantActiveIdx_ = targetIdx;
if numel(obj.variantUseCount_) >= targetIdx
    obj.variantUseCount_(targetIdx) = obj.variantUseCount_(targetIdx) + 1;
end

try
    obj.update_signal;
catch ME
    obj.variantActiveIdx_ = prevActiveIdx;
    obj.variantCycleActive_ = cycleWasActive;
    rethrow(ME)
end

obj.variantCycleActive_ = cycleWasActive;
obj.variantCurrentIdx_ = mod(targetIdx, nComb) + 1;

info = obj.get_variant_info();
