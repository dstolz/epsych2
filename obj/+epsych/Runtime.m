classdef Runtime < handle

    properties
        NSubjects (1,1) double {mustBeNonnegative,mustBeInteger} = 1

        % TO DO: REPLACE USINGSYNAPSE WITH GENERALIZED HWINUSE
        HWinUse (1,:) string
        usingSynapse (1,1) logical = false

        HW                % e.g., hw.TDT_RPcox
        TRIALS            % RuntimeTrials or struct-compatible
        dfltDataPath (1,1) string = ""
        HELPER            % e.g., epsych.Helper
        TIMER (1,1) timer % MATLAB timer object

        S                 % e.g., hw.Software
        CORE              % RuntimeCore or struct-compatible

        StartTime datetime = NaT
    end

    properties (SetObservable)
        ProgramState (1,1) PRGMSTATE = PRGMSTATE.NOCONFIG
        DataDir (1,1) string = ""
        DataFile string = strings(0,1)   % vector of filepaths
        onHold (1,1) logical = false
    end


    methods
        function self = Runtime
        

        end
    end
end

