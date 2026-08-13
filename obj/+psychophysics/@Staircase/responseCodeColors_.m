function c = responseCodeColors_(obj, decodedResponses, mask)
% c = responseCodeColors_(obj, decodedResponses, mask)
% Map the selected trials' response codes to hex colors for point markers.
%
% Takes the session's decode rather than raw codes so a plot update pays for
% one epsych.BitMask.decode over the trials instead of one per series.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   decodedResponses — epsych.BitMask.decode output over all trials, or []
%   mask — logical mask selecting the trials to color
%
% Returns:
%   c — Nx1 string array of hex colors, N = nnz(mask)

n = nnz(mask);
c = repmat(epsych.BitMask.getDefaultColors(epsych.BitMask.Undefined), n, 1);

if n == 0 || isempty(decodedResponses), return; end

for idx = 1:numel(obj.Bits)
    bitMask = decodedResponses.(char(obj.Bits(idx)));
    if numel(bitMask) ~= numel(mask), continue; end
    bitMask = bitMask(mask);
    if ~any(bitMask), continue; end
    c(bitMask) = obj.BitColors(idx);
end
