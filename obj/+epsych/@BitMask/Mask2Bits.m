function [bits, BM] = Mask2Bits(mask, nbits)
% [bits, BM] = epsych.BitMask.Mask2Bits(mask, nbits)
% Convert integer masks to logical bit arrays and active BitMask values.
% Parameters:
%   mask  - Integer array of nonnegative mask values to decode.
%   nbits - Optional number of bit positions to return. The default is 32.
% Returns:
%   bits - Logical array of size [numel(mask), nbits] with the least
%       significant bit in column 1.
%   BM   - Cell array, shaped like mask, containing active epsych.BitMask
%       values for each element.
%
% See also epsych.BitMask.Bits2Mask and documentation/epsych/epsych_BitMask.md.

arguments
    mask {mustBeNonnegative, mustBeFinite, mustBeNonempty, mustBeInteger}
    nbits (1,1) double {mustBePositive, mustBeInteger} = 32
end

inputSize = size(mask);
mask = uint32(mask(:));
n = numel(mask);
bitPositions = repmat(1:nbits, n, 1);
maskMatrix = repmat(mask, 1, nbits);

% Generate bits matrix
bitsFlat = logical(bitget(maskMatrix, bitPositions));

% Reshape bits to match input shape
bits = reshape(bitsFlat, [n, nbits]);

% Return BitMask if requested
if nargout == 2
    BM = arrayfun(@(idx) epsych.BitMask(find(bits(idx,:))), 1:n, 'UniformOutput', false);
    BM = reshape(BM, inputSize);
end
