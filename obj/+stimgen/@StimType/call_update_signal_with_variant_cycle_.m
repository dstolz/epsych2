function call_update_signal_with_variant_cycle_(obj)
% call_update_signal_with_variant_cycle_(obj)
% Wrap update_signal() to ensure exactly one deterministic variant selection
% per signal update call. Re-entrant calls (already inside a cycle) pass through.

cycleWasActive = obj.variantCycleActive_;
if ~cycleWasActive
    obj.begin_variant_cycle_();
end
try
    obj.update_signal;
catch ME
    if ~cycleWasActive
        obj.end_variant_cycle_();
    end
    rethrow(ME)
end
if ~cycleWasActive
    obj.end_variant_cycle_();
end
