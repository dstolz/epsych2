function tf = is_variant_policy_property_(obj, propName)
% tf = is_variant_policy_property_(obj, propName)
% Returns true if propName is a variant-policy property that should
% invalidate the variant cache without triggering a full signal recompute.
% Policy properties: VariantSelectionMode, VariantCombinationMode,
%   VariantSelectorClass, VariantSelectorConfig, VariantReselectOnUpdate.

POLICY_PROPS = ["VariantSelectionMode", "VariantCombinationMode", ...
                "VariantSelectorClass", "VariantSelectorConfig", ...
                "VariantReselectOnUpdate"];
tf = any(propName == POLICY_PROPS);
