


classdef Runtime < handle
    % epsych.Runtime
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
    %   getAllParameters    - Retrieve all parameters from hardware/software
    %
    % Example usage:
    %   r = epsych.Runtime;
    %   r.NSubjects = 2;
    %   r.writeParametersJSON('params.json');
    %
    % For more details, see:
    %   documentation/epsych_Runtime.md
    %   documentation/Architecture_Overview.md
    %   documentation/Parameter_Control.md
    %   documentation/EPsychInfo.md


    properties
        NSubjects (1,1) double {mustBeNonnegative,mustBeInteger} = 1 % Number of subjects in the experiment (default: 1)

        HWinUse (1,:) string % List of hardware in use (string array)
        usingSynapse (1,1) logical = false % True if using Synapse hardware

        TRIALS            % Protocol-specific trial information, including trial selection function, trial parameters, and trial count
        dfltDataPath (1,1) string = "" % Default data path for output
        HELPER            % Helper/event dispatcher object (e.g., epsych.Helper)
        TIMER (1,1) timer % MATLAB timer object for runtime services

        DATA (1,:) struct = struct.empty % Container for acquired data, updated at end of each trial

        DataDir (1,1) string = "" % Directory for acquired data
        DataFile string = strings(0,1)   % Filepath(s) for acquired data
        ON_HOLD (1,:) logical = false % Logical flag for hold state

        HW                % Hardware interface object(s) (e.g., hw.TDT_RPcox)
        S                 % Software interface object(s) (e.g., hw.Software)
        CORE              % Runtime core or struct-compatible

        StartTime datetime = NaT % Experiment start time (datetime)

        TrialComplete  % Manual trial completion flag (if in use, wait for manual completion of trial in RPvds)

        AcqBufferStr = "" % Buffer for acquired data (if in use, collect AcqBuffer data at end of trial)
    end


    


    methods
        % writeParametersJSON(obj, filepath)
        %   Serialize runtime parameters to a JSON file.
        %   See also: documentation/Parameter_Control.md
        writeParametersJSON(obj, filepath)

        % readParametersJSON(obj, filepath)
        %   Load runtime parameters from a JSON file.
        %   See also: documentation/Parameter_Control.md
        readParametersJSON(obj, filepath)

        function self = Runtime
            % self = Runtime
            % Construct an empty Runtime container and initialize state.
            vprintf(2, 'Initializing Runtime object')
        end

        function P = getAllParameters(obj, options)
            % P = getAllParameters(obj, options)
            % Retrieve all parameters from hardware and software interfaces.
            %
            % Parameters:
            %   obj (1,1) epsych.Runtime
            %       The runtime object.
            %   options.HW (1,1) logical
            %       Include hardware parameters (default: true)
            %   options.S (1,1) logical
            %       Include software parameters (default: true)
            %   options.includeTriggers (1,1) logical
            %       Include trigger parameters (default: false)
            %   options.includeInvisible (1,1) logical
            %       Include invisible parameters (default: false)
            %   options.includeArray (1,1) logical
            %       Include array-valued parameters (default: true)
            %   options.Access (1,1) char {mustBeMember(options.Access,{'Read','Write','Read / Write'})}
            %       Filter by access type (default: 'Read')
            %
            % Returns:
            %   P - Array of hw.Parameter objects
            %
            % See also: hw.Parameter, hw.Interface, documentation/Parameter_Control.md

            arguments
                obj
                options.HW (1,1) logical = true
                options.S (1,1) logical = true
                options.includeInvisible (1,1) logical = false
                options.includeTriggers (1,1) logical = false
                options.includeArray (1,1) logical = true
                options.Access (1,1) char {mustBeMember(options.Access,{'Read','Write','Read / Write'})} = 'Read'
            end

            if options.S
                vprintf(3, 'Retrieving all parameters from software interface')
                P = obj.S.all_parameters( ...
                        includeTriggers=options.includeTriggers, ...
                        includeInvisible=options.includeInvisible, ...
                        includeArray=options.includeArray, ...
                        Access=options.Access);
            end

            if options.HW
                for i = 1:numel(obj.HW)
                    vprintf(3, 'Retrieving all parameters from hardware interface: %s', class(obj.HW(i).Name))
                    P = [P, obj.HW(i).all_parameters( ...
                        includeTriggers=options.includeTriggers, ...
                        includeInvisible=options.includeInvisible, ...
                        includeArray=options.includeArray, ...
                        Access=options.Access)];
                end
            end
        end
    end

    methods (Static)
        function createTemplateJSON(filepath)
            % createTemplateJSON(filepath)
            % Create a template JSON phase file with example fields for hw.Parameter serialization.
            %
            % Parameters:
            %   filepath (1,:) string
            %       Full path to save the template JSON file. If not provided, prompts user to select location.
            %
            % Returns:
            %   None. Writes template JSON file to disk.
            %
            % Example usage:
            %   epsych.Runtime.createTemplateJSON('C:/path/to/template.json');
            %
            % The template includes example fields for hardware and software parameters.
            %
            % See also: documentation/Parameter_Control.md

            if nargin < 1 || isempty(filepath)
                [fn, pth] = uiputfile('*.json', 'Save Template Phase JSON As');
                if isequal(fn,0) || isequal(pth,0)
                    vprintf(3, 'User canceled template save operation.');
                    return
                end
                filepath = fullfile(pth, fn);
            end

            % Align template with hw.Parameter fields (see hw.Parameter and toStruct)
            templateParam = struct(...
                'Name', 'ExampleParam', ...
                'Description', "Example parameter for template", ...
                'Unit', '', ...
                'Module', '', ...
                'Access', 'Read / Write', ...
                'Type', 'Float', ...
                'Format', '%g', ...
                'Visible', true, ...
                'PreUpdateFcnEnabled', true, ...
                'EvaluatorFcnEnabled', true, ...
                'PostUpdateFcnEnabled', true, ...
                'isArray', false, ...
                'isTrigger', false, ...
                'isRandom', false, ...
                'Min', 0, ...
                'Max', 100, ...
                'Value', 0, ...
                'lastUpdated', 0 ...
            );

            comment = 'This JSON file is a template for hw.Parameter serialization. Duplicate the template entries and edit values as needed.';
            templateStruct = struct('Comment', comment, 'Parameters', templateParam);

            jsonStr = jsonencode(templateStruct, 'PrettyPrint', true);
            fid = fopen(filepath, 'w');
            if fid == -1
                error('Could not open file for writing: %s', filepath);
            end
            fwrite(fid, jsonStr, 'char');
            fclose(fid);
            vprintf(0, 'Template phase JSON file created at: %s', filepath);
        end
    end
end

