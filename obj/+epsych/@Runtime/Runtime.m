classdef Runtime < handle & dynamicprops
    % epsych.Runtime
    % Runtime state container for EPsych experiment execution.
    %
    % Stores experiment-wide state including subject count, trial metadata,
    % hardware/software interfaces, event dispatchers, and timer services.
    %
    % Properties:
    %   NSubjects      - Number of subjects in the experiment (default: 1)
    %   HWinUse        - List of hardware in use (string array)
    %   usingSynapse   - True if using Synapse hardware
    %   TRIALS         - Protocol-specific trial information
    %   dfltDataPath   - Default data path for output
    %   HELPER         - Helper/event dispatcher object
    %   TIMER          - MATLAB timer object for runtime services
    %   TempDataDir        - Directory for acquired data
    %   DataFile       - Filepath(s) for acquired data
    %   ON_HOLD        - Logical flag for hold state
    %   Interfaces
    %   HW             - Hardware interface object(s)
    %   S              - Software interface object(s)
    %   CORE           - Runtime core or struct-compatible
    %   StartTime      - Experiment start time (datetime)
    %   TrialComplete  - Manual trial completion flag
    %
    % Methods:
    %   Runtime             - Construct an empty runtime container
    %   writeParametersJSON - Write parameters to JSON file
    %   readParametersJSON  - Read parameters from JSON file
    %   all_parameters    - Retrieve all parameters from hardware/software
    %   updateTrialsFromParameters - Sync writable TRIALS fields from parameters
    %   createTemplateJSON  - Create a template JSON for parameter files
    %
    % Example usage:
    %   r = epsych.Runtime;
    %   r.NSubjects = 2;
    %   r.writeParametersJSON('params.json');
    %
    % For more details, see:
    %   documentation/epsych/epsych_Runtime.md
    %   documentation/overviews/Architecture_Overview.md
    %   documentation/gui/Parameter_Control.md
    %   documentation/epsych/EPsychInfo.md


    properties
        NSubjects (1,1) double {mustBePositive,mustBeInteger} = 1 % Number of subjects in the experiment (default: 1)

        HWinUse (1,:) string % List of hardware in use (string array)
        usingSynapse (1,1) logical = false % True if using Synapse hardware (TO DO: DEPRECATE in favor of checking for presence of Synapse in HW array)

        TRIALS            % Protocol-specific trial information, including trial selection function, trial parameters, and trial count
        dfltDataPath (1,1) string = "" % Default data path for output
        HELPER            % Helper/event dispatcher object (e.g., epsych.Helper)
        TIMER (1,1) timer % MATLAB timer object for runtime services


        TempDataDir (1,1) string = "" % Directory for acquired data
        DataFile string = strings(0,1)   % Filepath(s) for acquired data
        ON_HOLD (1,:) logical = false % Logical flag for hold state

        Interfaces        % Cell array of hardware and software interfaces (e.g., hw.TDT_RPcox, hw.Software)
        HW                % Hardware interface object(s) (e.g., hw.TDT_RPcox)
        S                 % Software interface object(s) (e.g., hw.Software)
        CORE              % Runtime core or struct-compatible

        StartTime datetime = NaT % Experiment start time (datetime)

        TrialComplete  % Manual trial completion flag (if in use, wait for manual completion of trial in RPvds)
    end


    


    methods
        % writeParametersJSON(obj, filepath)
        %   Serialize runtime parameters to a JSON file.
        %   See also: documentation/gui/Parameter_Control.md, documentation/epsych/epsych_Runtime.md
        writeParametersJSON(obj, filepath)

        % readParametersJSON(obj, filepath)
        %   Load runtime parameters from a JSON file.
        %   See also: documentation/gui/Parameter_Control.md, documentation/epsych/epsych_Runtime.md
        readParametersJSON(obj, filepath)

        function self = Runtime
            % self = Runtime
            % Construct an empty Runtime container and initialize state.
            vprintf(2, 'Initializing Runtime object')
        end

        function P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
            % P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
            % Filter Parameters by comparing a property to a target value.
            %
            % Parameters:
            %   obj           - hw.Interface. Hardware interface that owns the Parameters.
            %   propertyName  - char. Name of the hw.Parameter property to test.
            %   propertyValue - any. Target value or pattern passed to testFcn.
            %   options.testFcn - function_handle (default=@isequal). Comparator such as @isequal, @contains, or @startsWith.
            %   poptions.includeTriggers - logical (default=false). Include trigger Parameters in the candidate set.
            %   poptions.includeInvisible - logical (default=false). Include Parameters where Visible is false.
            %
            % Returns:
            %   P - hw.Parameter[]. Parameters whose selected property matches according to testFcn.
            %
            % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Parameter.md
            arguments
                obj
                propertyName (1,:) char
                propertyValue
                options.testFcn (1,1) function_handle = @isequal
                poptions.includeTriggers (1,1) logical = false
                poptions.includeInvisible (1,1) logical = false
            end
            poptions = namedargs2cell(poptions);
            P = obj.all_parameters(poptions{:});
            ind = arrayfun(@(a) obj.local_test(options.testFcn, a.(propertyName), propertyValue), P);
            P = P(ind);

        end

        % find_parameter - Return handle(s) to matching hw.Parameter objects by name
        function P = find_parameter(obj, name, options)
            % P = find_parameter(obj, name, options)
            % Return handle(s) to matching hw.Parameter objects by name.
            %
            % Parameters:
            %   obj    - hw.Interface. Hardware interface to search.
            %   name   - char | string | cellstr. Parameter name(s) to search for.
            %   options.includeInvisible - logical (default=false). Include Parameters where Visible is false.
            %   options.silenceParameterNotFound - logical (default=false). Suppress warning output when no matches are found.
            %
            % Returns:
            %   P - hw.Parameter[]. Matching Parameter handle(s) in requested name order. Empty if no match.
            %
            % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Parameter.md
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end
            P = obj.all_parameters(includeInvisible = options.includeInvisible);
            name = cellstr(name);
            ind = ismember({P.Name},name);
            if any(ind)
                P = P(ind);
                [ind,idx] = ismember(name,{P.Name});
                P = P(idx(ind));
            else
                P = [];
                if ~options.silenceParameterNotFound
                    cellfun(@(a) vprintf(0,1,'Parameter "%s" was not found on any modules',a),name)
                end
            end
        end
        function P = all_parameters(obj,optInt,options)
            % P = all_parameters(obj, options)
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
            %   options.Access (1,1) char {mustBeMember(options.Access,{'Read','Write','Any','All','Read / Write'})}
            %       Filter by access type (default: 'Read')
            %   options.asStruct (1,1) logical = false
            %       Return parameters as struct with valid field names instead of array (default: false)
            %
            % Returns:
            %   P - Array of hw.Parameter objects
            %
            % See also: hw.Parameter, hw.Interface, documentation/gui/Parameter_Control.md

            arguments
                obj
                optInt.HW (1,1) logical = true
                optInt.S (1,1) logical = true
                options.asStruct (1,1) logical = false
                options.includeInvisible (1,1) logical = false
                options.includeTriggers (1,1) logical = false
                options.includeArray (1,1) logical = true
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','All','Read / Write'})} = 'Read'
            end

            asStruct = options.asStruct;

            options = rmfield(options, 'asStruct');

            copts = namedargs2cell(options);
            if optInt.S
                vprintf(3, 'Retrieving all parameters from software interface')
                P = obj.S.all_parameters(copts{:});
            end

            if optInt.HW
                for i = 1:numel(obj.HW)
                    vprintf(3, 'Retrieving all parameters from hardware interface: %s', obj.HW(i).Type)
                    P = [P, obj.HW(i).all_parameters(copts{:})];
                end
            end

            if asStruct
                P_ = struct();
                for k = 1:numel(P)
                    P_.(P(k).validName) = P(k);
                end
                P = P_;
            end


        end

        function updateTrialsFromParameters(obj, Parameters)
            % updateTrialsFromParameters(obj, Parameters)
            % Update runtime TRIALS information based on current parameter values.
            %
            % Parameters:
            %   obj (1,1) epsych.Runtime
            %       The runtime object.
            %   Parameters (1,:) hw.Parameter
            %       Parameters used to update writable TRIALS fields.
            %
            % Returns:
            %   None. Updates obj.TRIALS in-place.
            %
            % See also: documentation/epsych/epsych_Runtime.md, documentation/gui/Parameter_Control.md

            arguments
                obj
                Parameters (1,:) hw.Parameter
            end

            ind = ismember({Parameters.Name}, obj.TRIALS.writeparams);
            Parameters(~ind) = [];

            vprintf(3, 'Updating TRIALS information from %d parameters: %s', numel(Parameters), strjoin({Parameters.Name},', '))
            for k = 1:numel(Parameters)
                pName = Parameters(k).Name;
                pVal = Parameters(k).Value;

                idx = obj.TRIALS.writeParamIdx.(pName);
                obj.TRIALS.trials(:,idx) = {pVal};
            end
        end
    end

    methods (Static)

        function tf = local_test(fcn, val, pat)
            % tf = local_test(fcn, val, pat)
            % Normalize comparison output to a logical scalar.
            %
            % Parameters:
            %   fcn - function_handle. Comparison function, e.g. @isequal, @contains.
            %   val - any. Value from the Parameter property.
            %   pat - any. Pattern/target value passed to the comparison function.
            %
            % Returns:
            %   tf - logical. True if the comparison indicates a match.
            %
            % See also: documentation/hw/hw_Interface.md
            res = fcn(val, pat);
            if islogical(res) && isscalar(res)
                tf = res;
            elseif isnumeric(res)
                % numeric (e.g. regexp indices) -> match if non-empty
                tf = ~isempty(res);
            elseif iscell(res)
                % cell of matches -> match if any non-empty element
                tf = any(~cellfun(@isempty, res));
            else
                tf = ~isempty(res);
            end
        end

    

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
            % See also: documentation/gui/Parameter_Control.md, documentation/epsych/epsych_Runtime.md

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
                'Access', 'Any', ...
                'Type', 'Float', ...
                'Format', '%g', ...
                'Visible', true, ...
                'PreUpdateFcn', 0, ...
                'EvaluatorFcn', 0, ...
                'PostUpdateFcn', 0, ...
                'PreUpdateFcnArgs', {[]}, ...
                'EvaluatorFcnArgs', {[]}, ...
                'PostUpdateFcnArgs', {[]}, ...
                'PreUpdateFcnEnabled', true, ...
                'EvaluatorFcnEnabled', true, ...
                'PostUpdateFcnEnabled', true, ...
                'isArray', false, ...
                'isTrigger', false, ...
                'isRandom', false, ...
                'Min', 0, ...
                'Max', 100, ...
                'Value', 0, ...
                'lastUpdated', 0, ...
                'ParentType', 'ExampleInterface' ... % Include ParentType for matching during load, even though it's not an actual field of hw.Parameter and is only used for matching to the correct interface during load
            );

            descr = 'This JSON file is a template for hw.Parameter serialization. Duplicate the template entries and edit values as needed.';
            templateStruct = struct('Description', descr, ...
                'Timestamp',datetime('now'), ...
                'Parameters', templateParam);

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


