function value = get_selected_property_value_(obj, propName)
% value = get_selected_property_value_(obj, propName)
% Return the scalar value for propName using the active variant combination.
% Scalar properties are returned as-is. For vectorized properties, the
% active variant index determines which element is returned.
%
% Parameters:
%   propName - Property name (char or string).
%
% Returns:
%   value - Scalar property value for the active variant.

if ~isprop(obj, char(propName))
    error('stimgen:StimType:UnknownProperty', 'Unknown property "%s".', char(propName));
end

raw = obj.(char(propName));
if obj.is_non_vectorizable_property_(propName) && numel(raw) > 1
    error('stimgen:StimType:NonVectorizableProperty', ...
        'Property "%s" is not vectorizable and must be scalar.', char(propName));
end

if numel(raw) <= 1
    value = raw;
    return
end

obj.refresh_variant_cache_if_needed_();
if isempty(obj.variantCombinationTable_)
    value = raw(1);
    return
end

idx = obj.variantActiveIdx_;
if ~obj.variantCycleActive_
    if obj.VariantReselectOnUpdate
        idx = obj.select_variant_index_();
        obj.variantActiveIdx_ = idx;
        if numel(obj.variantUseCount_) >= idx
            obj.variantUseCount_(idx) = obj.variantUseCount_(idx) + 1;
        end
    else
        if isempty(obj.variantCombinationTable_)
            idx = 1;
        else
            idx = min(max(obj.variantActiveIdx_, 1), numel(obj.variantCombinationTable_));
        end
    end
end

key = char(propName);
combo = obj.variantCombinationTable_(idx);
if isfield(combo, key)
    value = combo.(key);
else
    value = raw(1);
end
