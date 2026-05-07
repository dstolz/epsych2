function mask = Bits2Mask(bits, dim)
% mask = epsych.BitMask.Bits2Mask(bits, dim)
% Convert bit vectors or bit positions to uint32 masks.
% Parameters:
%   bits - Binary vectors with the least significant bit first, or vectors
%       of positive bit positions.
%   dim  - Dimension whose rows define independent masks. Use dim = 2 to
%       treat columns as independent masks.
% Returns:
%   mask - Column vector of uint32 mask values.
%
% Example:
%   mask = epsych.BitMask.Bits2Mask([0 1 1 1 0]);
%   mask = epsych.BitMask.Bits2Mask([2 3 4]);
%
% See also epsych.BitMask.Mask2Bits and documentation/epsych/epsych_BitMask.md.

arguments
    bits {mustBeNonempty}
    dim (1,1) double {mustBePositive,mustBeInteger,mustBeInRange(dim,1,2)} = 1
end

if dim == 2, bits = bits'; end

[nm,nb] = size(bits);
mask = zeros(nm,1,'uint32');
for i = 1:nm
    b = bits(i,:);

    if islogical(b) || all(b == 0 | b == 1)
        % Input is a binary vector
        weights = bitshift(uint32(1), 0:nb-1);
        mask(i) = sum(uint32(b) .* weights);
    elseif all(b == floor(b)) && all(b > 0)
        % Input is a vector of bit positions
        if any(b > 32)
            error('Bit positions must be in the range 1 to 32.');
        end
        mask(i) = sum(bitshift(uint32(1), b - 1));
    else
        error('Input must be a binary vector or a vector of positive integers.');
    end
end
