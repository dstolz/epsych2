function onPropertyChanged(obj, src, ~)
% onPropertyChanged(obj, src, event)
% Listener callback: update Signal and refresh plot when a property changes.
% Variant-policy property changes invalidate the cache but do not trigger
% a full signal recompute.

if ~isempty(src) && obj.is_variant_policy_property_(string(src.Name))
    % Policy edits should not force immediate signal recompute while
    % users are still configuring vectorized properties.
    obj.variantSignature_ = "";
    obj.variantSelectorObj_ = [];
    return
end
obj.call_update_signal_with_variant_cycle_(); % subclass implementation handles args
obj.refresh_plot_if_valid;
