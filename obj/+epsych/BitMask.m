classdef BitMask < uint32
    enumeration
        Undefined           (0)
        Hit                 (1)
        Miss                (2)
        CorrectReject       (3)
        FalseAlarm          (4)
        Abort               (5)
        Reward              (6)
        Punish              (7)
        PreResponseWindow   (8)
        ResponseWindow      (9)
        PostResponseWindow  (10)
        TrialType_0         (11)
        TrialType_1         (12)
        TrialType_2         (13)
        TrialType_3         (14)
        TrialType_4         (15)
        TrialType_5         (16)
        Choice_0            (17)
        Choice_1            (18)
        Choice_2            (19)
        Choice_3            (20)
        Choice_4            (21)
        Choice_5            (22)
        Option_A            (23)
        Option_B            (24)
        Option_C            (25)
        Option_D            (26)
        Option_E            (27)
        Option_F            (28)
        Option_G            (29)
        OPtion_H            (30)
        Option_I            (31)
    end

    methods
        function disp(obj)
            fprintf('Bit Index\tName\n');
            fprintf('---------\t----\n');
            for i = 1:length(obj)
                fprintf('  %7d\t%s\n', uint32(obj(i)), char(obj(i)));
            end
        end
    end

    methods (Static)
        function [names, values] = list()
            %LIST List all BitMask enumerations and their corresponding values.
            %
            %   [names, values] = epsych.BitMask.list() returns:
            %     - names  : Cell array of enumeration names (char)
            %     - values : Corresponding uint32 values
            %
            %   If no output is specified, the list is printed to the command window.
            %
            %   Example:
            %       epsych.BitMask.list()
            %
            %   See also: enumeration

            [enumObjs, names] = enumeration('epsych.BitMask');
            values = uint32(enumObjs);

            if nargout == 0
                disp(enumObjs)
                clear names values
            end
        end

        function f = GUI()
            f = bitmask_gui;
            if nargout == 0, clear f; end
        end


        function m = getResponses()
            m = epsych.BitMask(1:5);
        end

        function m = getContingencies()
            m = epsych.BitMask(6:7);
        end

        function m = getResponsePeriod()
            m = epsych.BitMask(8:10);
        end

        function m = getTrialTypes()
            m = epsych.BitMask(11:14);
        end

        function m = getChoices()
            m = epsych.BitMask(20:25);
        end

        function m = getOptions()
            m = epsych.BitMask(26:32);
        end

        function d = getDefined()
            d = epsych.BitMask.getAll;
            d(1) = [];
        end

        function a = getAll()
            a = enumeration('epsych.BitMask');
        end

        function tf = isValidValue(val)
            tf = any(uint32(enumeration('epsych.BitMask')) == val);
        end

        function [bits, BM] = Mask2Bits(mask, nbits)
            %MASK2BITS Convert integer bitmask(s) to binary array(s) and BitMask enum list(s).
            %
            %   bits = MASK2BITS(mask) returns a binary array of type uint8 with size
            %   [numel(mask), nbits], where each row represents the binary value of the
            %   corresponding element in 'mask', with the least significant bit (LSB) on the
            %   left (column 1).
            %
            %   bits = MASK2BITS(mask, nbits) specifies the number of bits to return
            %   instead of the default 32.
            %
            %   [bits, BM] = MASK2BITS(...) also returns a cell array 'BM' with the same
            %   shape as 'mask', where each cell contains an array of epsych.BitMask enums
            %   corresponding to the active bits in that mask element.
            %
            %   Inputs:
            %       mask  - Integer array (any size) of non-negative values to convert.
            %       nbits - (Optional) Number of bits to return (default = 32).
            %
            %   Outputs:
            %       bits - Array of size [numel(mask), nbits] representing binary state of each bit.
            %       BM   - Cell array of BitMask enumeration arrays indicating active flags.

            arguments
                mask (1,:) {mustBeNonnegative, mustBeFinite,mustBeNonempty,mustBeInteger}
                nbits (1,1) double = 32
            end

            mask = uint32(mask);

            % Flatten mask for processing
            mask = mask(:);
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
                BM = reshape(BM, size(mask));
            end
        end




        function mask = Bits2Mask(bits,dim)
            %BITS2MASK Convert a binary vector or bit positions to a scalar bitmask.
            %
            %   mask = BITS2MASK(bits) converts:
            %     - A binary vector (e.g., [0 1 1 1 0]) with LSB leftmost, or
            %     - A vector of bit positions (e.g., [2 3 4]) to a uint32 bitmask.
            %
            %  mask = BITS2MASK(bits, dim) specifies the dimension along which to
            %  interpret the input bits. For example, if bits is a 2D array with
            %  multiple rows, dim = 1 will treat each row as a separate binary
            %  vector, while dim = 2 will treat each column as a separate binary
            %  vector. The default is dim = 1.
            %
            %   Examples:
            %       mask = Bits2Mask([0 1 1 1 0]);    % -> 14
            %       mask = Bits2Mask([2 3 4]);        % -> 14
            %
            %  b = epsych.BitMask.Mask2Bits([Data.ResponseCode]);
            %  isequal(epsych.BitMask.Bits2Mask(b),[Data.ResponseCode]')
            %
            %   See also MASK2BITS, BITGET, BITSET.

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

        end


        function [M,N] = decodeResponseCodes(responseCodes)
            %DECODERESPONSECODES Decodes response codes into a structure of bitmask flags.
            %   [M, N] = DECODERESPONSECODES(RESPONSECODES) takes an array of response
            %   codes and decodes them using the bitmask definitions from
            %   epsych.BitMask.getDefined. The function returns a structure M where each
            %   field corresponds to a bitmask name and contains a logical array indicating
            %   the presence of that bit in each response code.
            %
            %   If two output arguments are requested, the function also returns N, a
            %   structure with the same fields as M, where each field contains the sum of
            %   true values in the corresponding field of M (i.e., the count of times each
            %   bitmask was set across all response codes).
            %
            %   Inputs:
            %       responseCodes - Array of integer response codes to decode.
            %
            %   Outputs:
            %       M - Structure with logical arrays for each bitmask flag.
            %       N - (Optional) Structure with counts for each bitmask flag.

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
        end


    end

end
