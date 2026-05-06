function info = set_variant_index(obj, idx)
% info = set_variant_index(obj, idx)
% Select a specific variant combination and regenerate Signal.
%
% Parameters:
%   idx - 1-based variant index (wraps cyclically).
%
% Returns:
%   info - Variant state struct.
arguments
    obj (1,1) stimgen.StimType
    idx (1,1) double {mustBeFinite,mustBePositive}
end

info = obj.apply_variant_index_and_update_(round(double(idx)));
