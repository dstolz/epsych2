classdef Runtime < handle

    properties
        NSubjects (1,1) double {mustBeNonnegative,mustBeInteger} = 1
        HWinUse (1,:) string

        HW                % e.g., hw.TDT_RPcox
        TRIALS            % RuntimeTrials or struct-compatible
        dfltDataPath (1,1) string = ""
        HELPER            % e.g., epsych.Helper
        TIMER (1,1) timer % MATLAB timer object

        DataDir (1,1) string = ""
        DataFile string = strings(0,1)   % vector of filepaths
        ON_HOLD (1,1) logical = false

        S                 % e.g., hw.Software
        CORE              % RuntimeCore or struct-compatible

        StartTime datetime = NaT
    end

    methods
        function self = Runtime
        

        end
    end
end

