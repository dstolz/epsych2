classdef BitMask < uint8

    enumeration
        Undefined       (0)
        Hit             (1)
        Miss            (2)
        CorrectReject   (3)
        FalseAlarm      (4)
        Abort           (5)
        Reward          (6)
        Punish          (7)
        PreResponseWindow   (8)
        ResponseWindow      (9)
        PostResponseWindow  (10)
        TrialType_0     (11)
        TrialType_1     (12)
        TrialType_2     (13)
        TrialType_3     (14)
        

    end

    
    methods (Static)
        function b = list
            b = epsych.BitMask(0:14);
            
            if nargout == 0
                for i = 1:length(b)
                    fprintf('% 2d\t%s\n',b(i),char(b(i)))
                end
            end
                
        end
    end
end