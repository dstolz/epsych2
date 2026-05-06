function signature = build_variant_signature_(obj, propNames, propValues)
% signature = build_variant_signature_(obj, propNames, propValues)
% Build a hash string from the current variant policy and property vectors.
% Used to detect when the combination table needs rebuilding.
%
% Parameters:
%   propNames  - 1-by-N string array of vectorized property names.
%   propValues - 1-by-N cell array of corresponding values.
%
% Returns:
%   signature - Delimited string encoding all inputs.

parts = strings(1, numel(propNames) + 3);
parts(1) = obj.VariantSelectionMode;
parts(2) = obj.VariantCombinationMode;
parts(3) = obj.VariantSelectorClass;
for k = 1:numel(propNames)
    v = propValues{k};
    if isnumeric(v) || islogical(v)
        vtxt = mat2str(v);
    elseif isstring(v)
        vtxt = strjoin(v, '|');
    elseif ischar(v)
        vtxt = string(v);
    else
        vtxt = string(class(v)) + ":" + string(numel(v));
    end
    parts(k+3) = propNames(k) + "=" + vtxt;
end
signature = strjoin(parts, "||");
