function S = toStruct(~, P)
% S = toStruct(obj, P)
% Convert one hw.Parameter to a struct safe for JSON serialization.
%
% Parameters
%   P - scalar hw.Parameter object
%
% Returns
%   S - struct with serialization-safe field values.

S = P.toStruct();
end