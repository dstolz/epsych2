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

        function P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
            % P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
            % Return hw.Parameter objects whose named property matches a target value.
            %
            % Parameters:
            %   obj                       - epsych.Runtime instance.
            %   propertyName              - Name of the hw.Parameter property to test.
            %   propertyValue             - Target value or pattern passed to testFcn.
            %   options.testFcn           - Comparator function (default: @isequal); e.g. @contains.
            %   poptions.includeTriggers  - Include trigger parameters (default: false).
            %   poptions.includeInvisible - Include invisible parameters (default: false).
            %
            % Returns:
            %   P - hw.Parameter array matching the filter criterion.
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
            % Return hw.Parameter handles matching the given name(s).
            %
            % Parameters:
            %   obj                               - epsych.Runtime instance.
            %   name                              - Parameter name(s); char, string, or cellstr.
            %   options.includeInvisible          - Include invisible parameters (default: false).
            %   options.silenceParameterNotFound  - Suppress not-found warnings (default: false).
            %
            % Returns:
            %   P - hw.Parameter array in requested name order; empty if no match.
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
        
        function P = all_parameters(obj, options)
            % P = all_parameters(obj, options)
            % Retrieve all parameters from all registered interfaces, with optional filtering.
            %
            % Parameters:
            %   obj                      - epsych.Runtime instance.
            %   options.includeTriggers  - Include trigger parameters (default: false).
            %   options.includeInvisible - Include invisible parameters (default: false).
            %   options.includeArray     - Include array-valued parameters (default: true).
            %   options.Access           - Filter by access: 'Read', 'Write', 'Any', 'All', 'Read / Write' (default: 'Read').
            %   options.asStruct         - Return as struct keyed by validName instead of array (default: false).
            %   options.Interface        - Char, string, or cellstr of class name(s) to restrict results to one or
            %                             more specific interface classes (default: {}, returns all interfaces).
            %
            % Returns:
            %   P - hw.Parameter array, or struct if asStruct is true.

            arguments
                obj
                options.asStruct (1,1) logical = false
                options.includeInvisible (1,1) logical = false
                options.includeTriggers (1,1) logical = false
                options.includeArray (1,1) logical = true
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','All','Read / Write'})} = 'Read'
                options.Interface = {}
            end

            asStruct = options.asStruct;
            options = rmfield(options, 'asStruct');

            interfaceFilter = cellstr(options.Interface);  % normalize to cellstr; empty cellstr means no filter
            
            options = rmfield(options, 'Interface');

            copts = namedargs2cell(options);
            P = hw.Parameter.empty;
            for i = 1:numel(obj.Interfaces)
                iface = obj.Interfaces{i};
                if ~isempty(interfaceFilter) && ~any(cellfun(@(c) isa(iface, c), interfaceFilter))
                    continue
                end
                vprintf(4, 'Retrieving all parameters from %s', class(iface))
                P = [P, iface.all_parameters(copts{:})];
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
            % Sync writable TRIALS fields from current parameter values. Updates obj.TRIALS in-place.
            %
            % Parameters:
            %   obj        - epsych.Runtime instance.
            %   Parameters - hw.Parameter array to sync from; non-writable entries are ignored.

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
            % Normalize any comparison result to a logical scalar.
            %
            % Parameters:
            %   fcn - Comparison function; e.g. @isequal, @contains, @regexp.
            %   val - Value from the Parameter property.
            %   pat - Pattern or target value passed to fcn.
            %
            % Returns:
            %   tf - True if fcn indicates a match.
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
            % Write a template JSON file with example hw.Parameter fields to disk.
            % Prompts for location if filepath is omitted.
            %
            % Parameters:
            %   filepath - Full path for the output JSON file (optional; opens uiputfile if empty).
            %
            % Example:
            %   epsych.Runtime.createTemplateJSON('C:/path/to/template.json');

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


