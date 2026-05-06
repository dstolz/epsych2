function v = selected_value(obj, propName)
% v = selected_value(obj, propName)
% Return the scalar value chosen for a potentially-vectorized property
% based on the currently active variant combination.
%
% Parameters:
%   propName - Name of the property (string).
%
% Returns:
%   v - Scalar value of the property for the active variant.
arguments
    obj (1,1) stimgen.StimType
    propName (1,1) string
end
v = obj.get_selected_property_value_(propName);
