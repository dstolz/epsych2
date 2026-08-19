classdef BitMask < uint32
    % bm = epsych.BitMask.Undefined
    % epsych.BitMask Enumerated bit indices used for EPsych trial and response coding.
    % This enumeration maps named behavioral states, contingencies, trial types,
    % choices, and options to bit positions used in uint32 response masks.
    %
    % Use epsych.BitMask to build masks, decode stored response codes, validate
    % enum values, and retrieve default colors for visualization.
    %
    % What the outcome bits mean depends on the task, and the two families
    % do not mix. getResponses lists the valid response types:
    %
    %   Detection (go / no-go, a stimulus or a catch trial)
    %     Hit           responded on a stimulus trial
    %     Miss          withheld on a stimulus trial
    %     FalseAlarm    responded on a catch trial
    %     CorrectReject withheld on a catch trial
    %
    %   Forced choice (N alternatives, every trial demands a response)
    %     Choice_k      which alternative was chosen -- and the ONLY bit
    %                   that carries which one it was
    %     Hit           that choice was the correct alternative
    %     Miss          the subject chose, and chose wrong
    %     (no bit)      no response at all: Undefined
    %     CorrectReject and FalseAlarm are NEVER used: there is no trial
    %                   with nothing to respond to.
    %
    %   Either way, Abort marks a response that arrived before the response
    %   window opened, TrialType_k names the trial's category (stimulus,
    %   catch, remind, ...), and Reward / Punish record the contingency the
    %   paradigm delivered rather than how the trial was scored.
    %
    % See psychophysics.Detection and psychophysics.NAFC, which read them.
    %
    % Example:
    %   flags = [epsych.BitMask.Hit epsych.BitMask.Reward];
    %   mask = epsych.BitMask.Bits2Mask(uint32(flags));
    %   [bits, activeFlags] = epsych.BitMask.Mask2Bits(mask);
    %
    % See also documentation/epsych/epsych_BitMask.md for additional examples and workflow notes.
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
            % See also documentation/epsych/epsych_BitMask.md for usage examples.

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
            % See also documentation/epsych/epsych_BitMask.md and helpers/bitmask_gui.m.
            arguments
                options.InitialMask (1,1) {mustBeNonnegative, mustBeFinite, mustBeInteger} = 0
            end
            f = bitmask_gui(InitialMask = options.InitialMask);
            if nargout == 0, clear f; end
        end

        function m = getResponses()
            % m = epsych.BitMask.getResponses()
            % Return the response outcome flags -- the valid response types.
            % Returns:
            %   m - epsych.BitMask array containing Hit, Miss, CorrectReject,
            %       FalseAlarm, and Abort.
            %
            % Use this rather than a hardcoded name list when code has to
            % ask "how was this trial scored". A trial carrying none of them
            % has no outcome: Undefined, which in a forced choice is how a
            % trial the subject never answered is recorded.
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

        colors = getDefaultColors(bitMasks) % Return default hex colors for BitMask values
        [bits, BM] = Mask2Bits(mask, nbits) % Convert integer masks to logical bit arrays and active BitMask values
        mask = Bits2Mask(bits, dim) % Convert bit vectors or bit positions to uint32 masks
        [M, N] = decode(responseCodes) % Decode response codes into named logical flag arrays

    end

end
