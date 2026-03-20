function S = parameterToStruct(~, P)
% S = parameterToStruct(obj, P)
% Convert one hw.Parameter to a struct safe for JSON serialization.
%
% Parameters
%   P - scalar hw.Parameter object
%
% Returns
%   S - struct with serialization-safe field values.

S = P.parameterToStruct();
end
