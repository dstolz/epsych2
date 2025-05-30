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
        Remind              (32)
    end

    methods
        function disp(obj)
            for i = 1:length(obj)
                fprintf('BitMask: (%d) %s\n', uint32(obj(i)), char(obj(i)));
            end
        end
    end

    methods (Static)
        function [n, values] = list()
            [m, n] = enumeration('epsych.BitMask');
            values = uint32(m);
            if nargout == 0
                for k = 1:numel(m)
                    fprintf('%2d\t%s\n', values(k), n{k});
                end
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


    end

end
