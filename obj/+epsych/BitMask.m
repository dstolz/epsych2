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

            narginchk(1, 2);

            % Validate 'mask' input
            if ~isnumeric(mask) || any(mask(:) ~= floor(mask(:))) || any(mask(:) < 0)
                error('Input ''mask'' must be an array of non-negative integers.');
            end

            % Set default 'nbits' if not provided
            if nargin < 2 || isempty(nbits)
                nbits = 32;
            end

            % Validate 'nbits' input
            if ~isscalar(nbits) || ~isnumeric(nbits) || nbits <= 0 || nbits ~= floor(nbits)
                error('Input ''nbits'' must be a positive scalar integer.');
            end

            % Flatten mask for processing
            maskFlat = mask(:);
            n = numel(maskFlat);
            bitPositions = repmat(1:nbits, n, 1);
            maskMatrix = repmat(maskFlat, 1, nbits);

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

        


        function mask = Bits2Mask(bits)
            %BITS2MASK Convert a binary vector or bit positions to a scalar bitmask.
            %
            %   mask = BITS2MASK(bits) converts:
            %     - A binary vector (e.g., [0 1 1 1 0]) with LSB leftmost, or
            %     - A vector of bit positions (e.g., [2 3 4]) to a uint32 bitmask.
            %
            %   Examples:
            %       mask = Bits2Mask([0 1 1 1 0]);    % -> 14
            %       mask = Bits2Mask([2 3 4]);        % -> 14
            %
            %   See also MASK2BITS, BITGET, BITSET.

            narginchk(1, 1);

            % Validate input
            if ~isvector(bits)
                error('Input must be a vector.');
            end

            bits = bits(:)';  % Ensure row vector

            if islogical(bits) || all(bits == 0 | bits == 1)
                % Input is a binary vector
                n = length(bits);
                weights = bitshift(uint32(1), 0:n-1);
                mask = sum(uint32(bits) .* weights);
            elseif all(bits == floor(bits)) && all(bits > 0)
                % Input is a vector of bit positions
                if any(bits > 32)
                    error('Bit positions must be in the range 1 to 32.');
                end
                mask = sum(bitshift(uint32(1), bits - 1));
            else
                error('Input must be a binary vector or a vector of positive integers.');
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

        bm = epsych.BitMask.getDefined;
        s = string(bm);
        for i = 1:length(bm)
            b = bitget(responseCodes,bm(i));
            m.(s(i)) = logical(b);
        end

        if nargout == 2
            n = struct(@sum,m);
        end
        end


    end

end
