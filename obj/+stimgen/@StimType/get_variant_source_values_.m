function [propNames, propValues] = get_variant_source_values_(obj)
% [propNames, propValues] = get_variant_source_values_(obj)
% Collect UserProperties that have more than one value (vectorized).
% Non-vectorizable properties and scalar properties are excluded.
%
% Returns:
%   propNames  - 1-by-N string array of vectorized property names.
%   propValues - 1-by-N cell array of corresponding row vectors.

propNames = string.empty(1,0);
propValues = {};
if isempty(obj.UserProperties)
    return
end

for k = 1:numel(obj.UserProperties)
    pname = string(obj.UserProperties(k));
    if ~isprop(obj, char(pname))
        continue
    end
    raw = obj.(char(pname));
    if obj.is_non_vectorizable_property_(pname)
        if numel(raw) > 1
            error('stimgen:StimType:NonVectorizableProperty', ...
                'Property "%s" is not vectorizable and must be scalar.', char(pname));
        end
        continue
    end
    if numel(raw) > 1
        propNames(end+1) = pname; %#ok<AGROW>
        if isrow(raw)
            propValues{end+1} = raw; %#ok<AGROW>
        else
            propValues{end+1} = reshape(raw, 1, []); %#ok<AGROW>
        end
    end
end
