function info = step_variant(obj, step)
% info = step_variant(obj)
% info = step_variant(obj, step)
% Step variant combination index and regenerate Signal.
%
% Parameters:
%   step - Signed integer step (default +1).
%
% Returns:
%   info - Variant state struct.
arguments
    obj (1,1) stimgen.StimType
    step (1,1) double {mustBeFinite,mustBeInteger} = 1
end

state = obj.get_variant_info();
info = obj.apply_variant_index_and_update_(state.ActiveIndex + step);
