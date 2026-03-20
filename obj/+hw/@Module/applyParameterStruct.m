function applyParameterStruct(~, P, S)
% applyParameterStruct(obj, P, S)
% Apply a decoded JSON struct onto an existing hw.Parameter.
%
% Parameters
%   P - scalar hw.Parameter handle to update
%   S - struct decoded from JSON with serialized parameter fields

P.applyParameterStruct(S);
end
