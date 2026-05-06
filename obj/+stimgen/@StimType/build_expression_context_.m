function context = build_expression_context_(obj, targetPropName)
% context = build_expression_context_(obj, targetPropName)
% Build a struct of current numeric UserProperty values for use as eval context.
% The target property is excluded to prevent self-reference.
%
% Parameters:
%   targetPropName - Name of the property being evaluated (excluded from context).
%
% Returns:
%   context - Struct mapping valid MATLAB names to double values.

context = struct();
if isempty(obj.UserProperties)
    return
end
for k_ = 1:numel(obj.UserProperties)
    pname = char(obj.UserProperties(k_));
    if strcmp(pname, targetPropName)
        continue
    end
    if ~isprop(obj, pname)
        continue
    end
    raw = obj.(pname);
    if isnumeric(raw) || islogical(raw)
        safeName = matlab.lang.makeValidName(pname);
        context.(safeName) = double(raw);
    end
end
