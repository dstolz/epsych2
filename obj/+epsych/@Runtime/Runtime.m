classdef Runtime < handle & dynamicprops
    % epsych.Runtime
    % Runtime state container for EPsych experiment execution.
    %
    % Stores experiment-wide state including subject count, trial metadata,
    % hardware/software interfaces, event dispatchers, and timer services.
    %
    % Key properties:
    %   NSubjects   - Number of subjects (default: 1)
    %   TRIALS      - Protocol trial data and selection state
    %   HW          - Hardware interface object(s)
    %   S           - Software interface object(s)
    %   HELPER      - Event dispatcher object
    %   TIMER       - Timer object for runtime services
    %
    % Key methods:
    %   Runtime                    - Construct an empty runtime container
    %   writeParametersJSON        - Serialize runtime parameters to JSON
    %   readParametersJSON         - Load runtime parameters from JSON
    %   all_parameters             - Retrieve all hardware/software parameters
    %   updateTrialsFromParameters - Sync writable TRIALS fields from parameters
    %   createTemplateJSON         - Create a template JSON for parameter files
    %
    % Usage:
    %   r = epsych.Runtime;
    %   r.NSubjects = 2;
    %   r.writeParametersJSON('params.json');


    properties
        NSubjects (1,1) double {mustBePositive,mustBeInteger} = 1 % Number of subjects in the experiment (default: 1)

        HWinUse (1,:) string % List of hardware in use (string array)

        TRIALS            % Protocol-specific trial information, including trial selection function, trial parameters, and trial count
        dfltDataPath (1,1) string = "" % Default data path for output
        HELPER            % Helper/event dispatcher object (e.g., epsych.Helper)
        TIMER (1,1) timer % MATLAB timer object for runtime services


        TempDataDir (1,1) string = "" % Directory for acquired data
        DataFile string = strings(0,1)   % Filepath(s) for acquired data

        Interfaces        % Cell array of hardware and software interfaces (e.g., hw.TDT_RPcox, hw.Software)
        HW                % Hardware interface object(s) (e.g., hw.TDT_RPcox)
        S                 % Software interface object(s) (e.g., hw.Software)
        CORE              % Runtime core or struct-compatible

        StartTime datetime = NaT % Experiment start time (datetime)

        TrialComplete  % Manual trial completion flag (if in use, wait for manual completion of trial in RPvds)
    end


    


    methods
        writeParametersJSON(obj, filepath)      % Serialize runtime parameters to a JSON file.
        readParametersJSON(obj, filepath)       % Load runtime parameters from a JSON file.
        dispatchNextTrial(obj, subjectIdx)      % Dispatch the already selected next trial for one subject.
        resolveCoreParameters(obj, subjectIdx)  % Locate and cache mandatory trigger parameters (NewTrial, ResetTrig, TrialComplete) for one subject.

        function self = Runtime
            % self = Runtime
            % Construct an empty Runtime container and initialize state.
            vprintf(2, 'Initializing Runtime object')
        end

        filter_parameters(obj, propertyName, propertyValue, options, poptions) % Return hw.Parameter objects whose named property matches a target value.
        find_parameter(obj, name, options)              % Return hw.Parameter handles matching the given name(s), with optional pre-filtering.
        P = all_parameters(obj, options)                % Retrieve all parameters from all registered interfaces, with optional filtering.
        updateTrialsFromParameters(obj, Parameters)     % Sync writable TRIALS fields from current parameter values.
    end

    methods (Static)
        tf = local_test(fcn, val, pat)      % Normalize any comparison result to a logical scalar.
        createTemplateJSON(filepath)        % Write a template JSON file with example hw.Parameter fields to disk.
    end
end


