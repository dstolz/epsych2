function refresh_variant_cache_if_needed_(obj)
% refresh_variant_cache_if_needed_(obj)
% Rebuild the variant combination table when the property signature has changed.
% No-op when the signature matches the cached value.

[propNames, propValues] = obj.get_variant_source_values_();
signature = obj.build_variant_signature_(propNames, propValues);
if signature == obj.variantSignature_
    return
end

[comboTable, comboProps] = obj.build_variant_combinations_(propNames, propValues);
obj.variantCombinationTable_ = comboTable;
obj.variantCombinationPropNames_ = comboProps;
obj.variantUseCount_ = zeros(1, numel(comboTable));
obj.variantCurrentIdx_ = 1;
obj.variantActiveIdx_ = 1;
obj.variantSignature_ = signature;
obj.variantSelectorObj_ = [];
