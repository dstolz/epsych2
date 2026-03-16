classdef Runtime < handle
    % r = epsych.Runtime()
    % Runtime container for EPsych experiment execution state.
    %
    % This class holds experiment-wide runtime state such as subject count,
    % trial metadata, hardware interfaces, helper event dispatch, and the
    % MATLAB timer used by GUI / runtime services.
    %
    % Properties:
    %   TRIALS, HW, S, CORE - Primary runtime components.
    %   HELPER, TIMER       - Helper/event dispatcher and timer handle.
    %   DataDir, DataFile   - Output location(s) for acquired data.
    %
    % Methods:
    %   Runtime             - Construct an empty runtime container.

    properties
        NSubjects (1,1) double {mustBeNonnegative,mustBeInteger} = 1


        % TO DO: REPLACE USINGSYNAPSE WITH GENERALIZED HWINUSE
        HWinUse (1,:) string
        usingSynapse (1,1) logical = false

        TRIALS            % Protocol-specific trial information, including trial selection function, trial parameters, and trial count
        dfltDataPath (1,1) string = ""
        HELPER            % e.g., epsych.Helper
        TIMER (1,1) timer % MATLAB timer object

        DataDir (1,1) string = ""
        DataFile string = strings(0,1)   % vector of filepaths
        ON_HOLD (1,:) logical = false

        HW                % e.g., hw.TDT_RPcox
        S                 % e.g., hw.Software
        CORE              % RuntimeCore or struct-compatible

        StartTime datetime = NaT

        TrialComplete  % If in use, wait for manual completion of trial in RPvds

        AcqBufferStr = "" % If in use, collect AcqBuffer data at end of trial
    end


    

    methods
        function self = Runtime
            vprintf(2,'Initializing Runtime object')

        end
    end
end

