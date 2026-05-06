function end_variant_cycle_(obj)
% end_variant_cycle_(obj)
% Release the variant cycle lock after a signal update call completes.

obj.variantCycleActive_ = false;
