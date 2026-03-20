function fromStruct(~, P, S)
% fromStruct(obj, P, S)
% Apply a decoded JSON struct onto an existing hw.Parameter.
%
% Parameters
%   P - scalar hw.Parameter handle to update
%   S - struct decoded from JSON with serialized parameter fields

P.fromStruct(S);
end