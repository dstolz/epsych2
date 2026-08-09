function [M, N] = decode(responseCodes)
% [M, N] = epsych.BitMask.decode(responseCodes)
% Decode response codes into named logical flag arrays.
% Parameters:
%   responseCodes - Integer array of response masks to decode.
% Returns:
%   M - Structure with one logical field per defined BitMask member.
%   N - Structure of per-field counts, returned when requested.
%
% The Undefined member is excluded from the output fields. See also
% documentation/epsych/epsych_BitMask.md for common decoding workflows.

responseCodes = uint32(responseCodes);
bm = epsych.BitMask.getDefined;
s = string(bm);
bm = uint32(bm);
for i = 1:length(bm)
    b = bitget(responseCodes,bm(i));
    M.(s(i)) = logical(b);
end

if nargout == 2
    N = structfun(@sum,M,'uni',0);
end
