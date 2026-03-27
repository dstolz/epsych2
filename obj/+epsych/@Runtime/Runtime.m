
classdef Runtime < handle
    % r = epsych.Runtime()
    % Container for EPsych experiment execution runtime state.
    %
    % Holds experiment-wide state including subject count, trial metadata, hardware interfaces, event dispatchers, and the MATLAB timer for GUI/runtime services.
    %
    % Properties:
    %   NSubjects      - Number of subjects in the experiment (default: 1)
    %   HWinUse        - List of hardware in use (string array)
    %   usingSynapse   - True if using Synapse hardware
    %   TRIALS         - Protocol-specific trial information
    %   dfltDataPath   - Default data path for output
    %   HELPER         - Helper/event dispatcher object
    %   TIMER          - MATLAB timer object for runtime services
    %   DataDir        - Directory for acquired data
    %   DataFile       - Filepath(s) for acquired data
    %   ON_HOLD        - Logical flag for hold state
    %   HW             - Hardware interface object(s)
    %   S              - Software interface object(s)
    %   CORE           - Runtime core or struct-compatible
    %   StartTime      - Experiment start time (datetime)
    %   TrialComplete  - Manual trial completion flag
    %   AcqBufferStr   - Buffer for acquired data (if used)
    %
    % Methods:
    %   Runtime             - Construct an empty runtime container
    %   writeParametersJSON - Write parameters to JSON file
    %   readParametersJSON  - Read parameters from JSON file
    %
    % Example:
    %   r = epsych.Runtime();
    %   r.NSubjects = 2;
    %   r.writeParametersJSON('params.json');
    %
    % See also: epsych, hw.Parameter

    properties
        NSubjects (1,1) double {mustBeNonnegative,mustBeInteger} = 1


        % TO DO: REPLACE USINGSYNAPSE WITH GENERALIZED HWINUSE
        HWinUse (1,:) string
        usingSynapse (1,1) logical = false

        TRIALS            % Protocol-specific trial information, including trial selection function, trial parameters, and trial count
        dfltDataPath (1,1) string = ""
        HELPER            % e.g., epsych.Helper
        TIMER (1,1) timer % MATLAB timer object


        DATA (1,:) struct = struct.empty % Container for acquired data, updated at end of each trial

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
        % writeParametersJSON(obj, filepath)
        %   Serialize runtime parameters to a JSON file.
        writeParametersJSON(obj, filepath)

        % readParametersJSON(obj, filepath)
        %   Load runtime parameters from a JSON file.
        readParametersJSON(obj, filepath)

        function self = Runtime
            % self = Runtime
            % Construct an empty Runtime container and initialize state.
            vprintf(2,'Initializing Runtime object')
        end

        function P = getAllParameters(obj,options)
            % getAllParameters(obj)
            % Retrieve all parameters from hardware and software interfaces.

            arguments
                obj
                options.HW (1,1) logical = true
                options.S (1,1) logical = true
                options.includeInvisible (1,1) logical = false
                options.includeTriggers (1,1) logical = false
                options.includeArray (1,1) logical = true
                options.Access (1,1) char {mustBeMember(options.Access,{'Read','Write','Read / Write'})} = 'Read / Write'
            end

            if options.S
                 vprintf(3,'Retrieving all parameters from software interface')
                P = obj.S.all_parameters( ...
                        includeTriggers=options.includeTriggers, ...
                        includeInvisible=options.includeInvisible, ...
                        includeArray=options.includeArray, ...
                        Access=options.Access);
            end

            if options.HW
                for i = 1:numel(obj.HW)
                    vprintf(3,'Retrieving all parameters from hardware interface: %s', class(obj.HW(i).Name))
                    P = [P, obj.HW(i).all_parameters( ...
                        includeTriggers=options.includeTriggers, ...
                        includeInvisible=options.includeInvisible, ...
                        includeArray=options.includeArray, ...
                        Access=options.Access)];
                end
            end
        end
    end
end

