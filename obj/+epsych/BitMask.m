classdef BitMask < uint32
    % bm = epsych.BitMask.Undefined
    % epsych.BitMask Enumerated bit indices used for EPsych trial and response coding.
    % This enumeration maps named behavioral states, contingencies, trial types,
    % choices, and options to bit positions used in uint32 response masks.
    %
    % Use epsych.BitMask to build masks, decode stored response codes, validate
    % enum values, and retrieve default colors for visualization.
    %
    % Example:
    %   flags = [epsych.BitMask.Hit epsych.BitMask.Reward];
    %   mask = epsych.BitMask.Bits2Mask(uint32(flags));
    %   [bits, activeFlags] = epsych.BitMask.Mask2Bits(mask);
    %
    % See also documentation/BitMask.md for additional examples and workflow notes.
    %
    % Methods:
    %   list             - Return or print enumeration names and bit indices.
    %   GUI              - Launch the interactive bitmask GUI helper.
    %   getResponses     - Return response outcome flags.
    %   getContingencies - Return contingency flags.
    %   getResponsePeriod - Return response window flags.
    %   getTrialTypes    - Return trial type flags.
    %   getChoices       - Return choice flags.
    %   getOptions       - Return option flags.
    %   getDefined       - Return all defined flags except Undefined.
    %   getAll           - Return all enumeration members.
    %   isValidValue     - Test whether a value is a defined enum member.
    %   getDefaultColors - Return default hex colors for enum values.
    %   Mask2Bits        - Convert integer masks to logical bit arrays.
    %   Bits2Mask        - Convert bit arrays or bit positions to uint32 masks.
    %   decode           - Decode masks into a struct with named logical fields.
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
        Option_H            (30)
        Option_I            (31)
    end

    methods
        function disp(obj)
            % disp(obj)
            % Display BitMask values as a bit-index table.
            % Parameters:
            %   obj - epsych.BitMask array to display.
            fprintf('Bit Index\tName\n');
            fprintf('---------\t----\n');
            for i = 1:length(obj)
                fprintf('  %7d\t%s\n', uint32(obj(i)), char(obj(i)));
            end
        end
    end

    methods (Static)
        function [names, values] = list()
            % [names, values] = epsych.BitMask.list()
            % Return or print all BitMask enumeration names and bit indices.
            % Parameters:
            %   None.
            % Returns:
            %   names  - Cell array of enumeration member names.
            %   values - uint32 array of corresponding bit indices.
            %
            % When called with no output arguments, the method prints the full list.
            % See also documentation/BitMask.md for usage examples.

            [enumObjs, names] = enumeration('epsych.BitMask');
            values = uint32(enumObjs);

            if nargout == 0
                disp(enumObjs)
                clear names values
            end
        end

        function f = GUI(options)
            % f = epsych.BitMask.GUI(options)
            % Launch the interactive bitmask GUI helper.
            % Parameters:
            %   options.InitialMask - Optional uint32-compatible scalar mask loaded into
            %       the GUI at startup.
            % Returns:
            %   f - Figure handle for the launched GUI.
            %
            % See also documentation/BitMask.md and helpers/bitmask_gui.m.
            arguments
                options.InitialMask (1,1) {mustBeNonnegative, mustBeFinite, mustBeInteger} = 0
            end
            f = bitmask_gui(InitialMask = options.InitialMask);
            if nargout == 0, clear f; end
        end


        function m = getResponses()
            % m = epsych.BitMask.getResponses()
            % Return the response outcome flags.
            % Returns:
            %   m - epsych.BitMask array containing Hit, Miss, CorrectReject,
            %       FalseAlarm, and Abort.
            m = epsych.BitMask(1:5);
        end

        function m = getContingencies()
            % m = epsych.BitMask.getContingencies()
            % Return the contingency flags.
            % Returns:
            %   m - epsych.BitMask array containing Reward and Punish.
            m = epsych.BitMask(6:7);
        end

        function m = getResponsePeriod()
            % m = epsych.BitMask.getResponsePeriod()
            % Return the response-period flags.
            % Returns:
            %   m - epsych.BitMask array containing PreResponseWindow,
            %       ResponseWindow, and PostResponseWindow.
            m = epsych.BitMask(8:10);
        end

        function m = getTrialTypes()
            % m = epsych.BitMask.getTrialTypes()
            % Return the trial-type flags.
            % Returns:
            %   m - epsych.BitMask array containing TrialType_0 through TrialType_5.
            m = epsych.BitMask(11:16);
        end

        function m = getChoices()
            % m = epsych.BitMask.getChoices()
            % Return the choice flags.
            % Returns:
            %   m - epsych.BitMask array containing Choice_0 through Choice_5.
            m = epsych.BitMask(17:22);
        end

        function m = getOptions()
            % m = epsych.BitMask.getOptions()
            % Return the option flags.
            % Returns:
            %   m - epsych.BitMask array containing Option_A through Option_I.
            m = epsych.BitMask(23:31);
        end

        function d = getDefined()
            % d = epsych.BitMask.getDefined()
            % Return all defined flags except Undefined.
            % Returns:
            %   d - epsych.BitMask array containing all nonzero enum members.
            d = epsych.BitMask.getAll;
            d(1) = [];
        end

        function a = getAll()
            % a = epsych.BitMask.getAll()
            % Return all BitMask enumeration members.
            % Returns:
            %   a - epsych.BitMask array including Undefined.
            a = enumeration('epsych.BitMask');
        end

        function tf = isValidValue(val)
            % tf = epsych.BitMask.isValidValue(val)
            % Test whether a numeric value matches a defined BitMask member.
            % Parameters:
            %   val - Numeric value to test against the enumeration values.
            % Returns:
            %   tf - Logical scalar or array indicating whether each value is valid.
            tf = any(uint32(enumeration('epsych.BitMask')) == val);
        end

        function colors = getDefaultColors(bitMasks)
            % colors = epsych.BitMask.getDefaultColors(bitMasks)
            % Return default hex colors for BitMask values.
            % Parameters:
            %   bitMasks - Optional epsych.BitMask array or numeric array of valid enum
            %       values. If omitted, colors are returned for all enum members.
            % Returns:
            %   colors - String array of hex color values matching the size of bitMasks.
            %
            % See also documentation/BitMask.md for grouped usage examples.

            if nargin < 1 || isempty(bitMasks)
                bitMasks = epsych.BitMask.getAll;
            end

            if isa(bitMasks, 'epsych.BitMask')
                bitValues = uint32(bitMasks);
            else
                if ~isnumeric(bitMasks) || ~all(isfinite(bitMasks(:))) || ~all(bitMasks(:) == floor(bitMasks(:)))
                    error('bitMasks must be an epsych.BitMask array or integer numeric values.');
                end
                bitValues = uint32(bitMasks);
            end

            allMasks = epsych.BitMask.getAll;
            allValues = uint32(allMasks);
            defaultColors = [...
                "#b8b8b8"; ... % Undefined
                "#1fa050"; ... % Hit
                "#db3939"; ... % Miss
                "#0d42f0"; ... % CorrectReject
                "#ff8800"; ... % FalseAlarm
                "#585757"; ... % Abort
                "#18b368"; ... % Reward
                "#7a2338"; ... % Punish
                "#8ecae6"; ... % PreResponseWindow
                "#219ebc"; ... % ResponseWindow
                "#023047"; ... % PostResponseWindow
                "#264653"; ... % TrialType_0
                "#2a9d8f"; ... % TrialType_1
                "#e9c46a"; ... % TrialType_2
                "#f4a261"; ... % TrialType_3
                "#e76f51"; ... % TrialType_4
                "#8ab17d"; ... % TrialType_5
                "#3a86ff"; ... % Choice_0
                "#8338ec"; ... % Choice_1
                "#ff006e"; ... % Choice_2
                "#fb5607"; ... % Choice_3
                "#ffbe0b"; ... % Choice_4
                "#6a994e"; ... % Choice_5
                "#003049"; ... % Option_A
                "#d62828"; ... % Option_B
                "#f77f00"; ... % Option_C
                "#fcbf49"; ... % Option_D
                "#2a9d8f"; ... % Option_E
                "#577590"; ... % Option_F
                "#90be6d"; ... % Option_G
                "#9b5de5"; ... % Option_H
                "#f15bb5"];    % Option_I

            [tf, loc] = ismember(bitValues(:), allValues);
            if ~all(tf)
                error('bitMasks contains values that are not defined in epsych.BitMask.');
            end

            colors = reshape(defaultColors(loc), size(bitValues));
        end

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
            % See also epsych.BitMask.Bits2Mask and documentation/BitMask.md.

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
        end




        function mask = Bits2Mask(bits,dim)
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
            % See also epsych.BitMask.Mask2Bits and documentation/BitMask.md.

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


        function [M,N] = decode(responseCodes)
            % [M, N] = epsych.BitMask.decode(responseCodes)
            % Decode response codes into named logical flag arrays.
            % Parameters:
            %   responseCodes - Integer array of response masks to decode.
            % Returns:
            %   M - Structure with one logical field per defined BitMask member.
            %   N - Structure of per-field counts, returned when requested.
            %
            % The Undefined member is excluded from the output fields. See also
            % documentation/BitMask.md for common decoding workflows.

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
