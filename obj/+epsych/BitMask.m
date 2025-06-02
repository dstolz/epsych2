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
        Choice_0            (20)
        Choice_1            (21)
        Choice_2            (22)
        Choice_3            (23)
        Choice_4            (24)
        Choice_5            (25)
        None                (30)
        Remind              (31)
    end

    methods
        function disp(obj)
            fprintf('BitMask Enumeration Members:\n');
            fprintf('  Value\tName\n');
            fprintf('  -----\t----\n');
            for i = 1:length(obj)
                fprintf('  %5d\t%s\n', uint32(obj(i)), char(obj(i)));
            end

        end
    end

    methods (Static)
        function [names, values, tbl] = list()
            %LIST List all BitMask enumerations and their corresponding values.
            %
            %   [names, values, tbl] = epsych.BitMask.list() returns:
            %     - names  : Cell array of enumeration names (char)
            %     - values : Corresponding uint32 values
            %     - tbl    : A table with 'Value' and 'Name' columns
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
            else
                tbl = table(values(:), names(:), 'VariableNames', {'Value', 'Name'});
            end
        end


        function m = getResponses()
            m = epsych.BitMask(1:5);
        end

        function m = getContingencies()
            m = epsych.BitMask([6 7 30]);
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

        function a = getAll()
            a = enumeration('epsych.BitMask');
        end

        function tf = isValidValue(val)
            tf = any(uint32(enumeration('epsych.BitMask')) == val);
        end


        function [bits,BM] = Mask2Bits(mask, nbits)
            %MASK2BITS Convert a scalar integer mask to a binary bit array.
            %
            %   bits = MASK2BITS(mask) returns a 32-element row vector of uint8
            %   containing the binary representation of the scalar integer 'mask',
            %   with the least significant bit (LSB) on the left.
            %
            %   bits = MASK2BITS(mask, nbits) returns a row vector of length 'nbits'.
            %
            %   Example:
            %       bits = Mask2Bits(14);        % Returns [0 0 0 ... 1 1 1 0]
            %       bits = Mask2Bits(14, 8);     % Returns [0 0 0 0 1 1 1 0]
            %
            %   See also BITGET, BITS2MASK.

            narginchk(1, 2);


            % Validate 'mask' input
            if ~isscalar(mask) || ~isnumeric(mask) || mask ~= floor(mask)
                error('Input ''mask'' must be a scalar integer value.');
            end

            % Set default 'nbits' if not provided
            if nargin < 2 || isempty(nbits)
                nbits = 32;
            end

            % Validate 'nbits' input
            if ~isscalar(nbits) || ~isnumeric(nbits) || nbits <= 0 || nbits ~= floor(nbits)
                error('Input ''nbits'' must be a positive scalar integer.');
            end

            % Generate bit positions from LSB to MSB
            bitPositions = 1:nbits;

            % Extract bits using vectorized 'bitget'
            bits = uint8(bitget(mask, bitPositions));


            if nargout == 2
                BM = epsych.BitMask(find(bits));
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



    end

end
