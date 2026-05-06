function info = get_variant_info(obj)
% info = get_variant_info(obj)
% Return current variant-combination state for this stimulus.
%
% Returns:
%   info.NumCombinations - Number of variant combinations.
%   info.ActiveIndex     - Active 1-based combination index.
%   info.PropertyNames   - Vectorized property names.

obj.refresh_variant_cache_if_needed_();

nComb = numel(obj.variantCombinationTable_);
if nComb < 1
    nComb = 1;
end

activeIdx = min(max(obj.variantActiveIdx_, 1), nComb);
info = struct(...
    'NumCombinations', nComb, ...
    'ActiveIndex', activeIdx, ...
    'PropertyNames', obj.variantCombinationPropNames_);
