function apply_gate(obj)
% apply_gate(obj)
% Apply onset/offset cosine-squared window to obj.Signal.
% Has no effect when ApplyWindow is false or temporarilyDisableSignalMods is true.

applyWindowValue = logical(obj.get_selected_property_value_("ApplyWindow"));
if ~applyWindowValue || obj.temporarilyDisableSignalMods, return; end

g = obj.Window;

n = length(g);
ga = g(1:n/2);
gb = g(n/2+1:end);

obj.Signal(1:n/2) = obj.Signal(1:n/2) .* ga;
obj.Signal(end-n/2+1:end) = obj.Signal(end-n/2+1:end) .* gb;
