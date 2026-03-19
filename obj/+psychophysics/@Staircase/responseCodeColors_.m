function c = responseCodeColors_(obj, responseCodes)
% c = responseCodeColors_(obj, responseCodes)
% Map response codes to hex colors for staircase point markers.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   responseCodes — numeric vector of encoded response codes
%
% Returns:
%   c — Nx1 string array of hex colors

n = numel(responseCodes);
c = repmat(epsych.BitMask.getDefaultColors(epsych.BitMask.Undefined), n, 1);

if n == 0, return; end

    
decoded = epsych.BitMask.decode(responseCodes);

for idx = 1:numel(obj.Bits)
    bitName = char(obj.Bits(idx));
    bitMask = decoded.(bitName);
    if ~any(bitMask), continue; end
    c(bitMask) = obj.BitColors(idx);
end