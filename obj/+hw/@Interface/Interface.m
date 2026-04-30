

classdef Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet
    % Abstract base class for EPsych hardware interfaces.
    %
    % Concrete subclasses expose one or more hw.Module objects and implement
    % connection, parameter I/O, and trigger operations behind a common API.
    %
    % Important properties:
    %   Module      - Modules owned by the interface.
    %   Type        - Constant interface identifier.
    %   mode        - Current hw.DeviceState for the backend.
    %   IsConnected - True when the backend connection is ready.
    %
    % Key methods:
    %   add_parameter  - Add a parameter through the shared interface API.
    %   all_parameters - Return parameters across all modules.
    %   find_parameter - Resolve parameters by name.
    %   connect        - Establish the backend connection.
    %   trigger        - Issue a named hardware event.
    %
    % Documentation: documentation/hw/hw_Interface.md

    properties (Abstract,SetAccess = protected)
        Module
    end

    properties (Abstract,Constant)
        Type
    end

    properties (Abstract,SetObservable,AbortSet)
        mode
    end

    properties (Abstract)
        IsConnected (1,1) logical   % true when the backend is connected and ready
    end


    properties
        h_listeners
    end



    methods (Abstract,Access = protected)
        % close_interface()
        %   Release backend resources.
        close_interface()

        % setup_interface()
        %   Allocate or connect backend resources.
        setup_interface()
    end


    methods (Abstract)
        % value = get_parameter(name)
        %   Read current value for one or more hardware parameters.
        value  = get_parameter(name)

        % result = set_parameter(name, value)
        %   Set new value for one or more hardware parameters.
        %   Returns true if successful and false otherwise.
        result = set_parameter(name,value)

        % result = trigger(name)
        %   Trigger a named hardware event.
        result = trigger(name)

        % connect()
        %   Establish a connection to the hardware backend.
        %   Sets IsConnected to true on success.
        connect()
    end

    methods (Abstract, Static)
        % spec = getCreationSpec()
        %   Return a hw.InterfaceSpec describing the options required to create this
        %   interface, including defaults, UI control hints, and a factory function.
        %   Each spec.options entry may include fields such as:
        %     name, label, defaultValue, required, inputType, choices,
        %     isList, scope, allowScalarExpansion, controlType, getFile,
        %     getFolder, fileFilter, fileDialogTitle, and description.
        %   controlType is optional and can be used to steer GUIs toward a
        %   specific widget such as text, textarea, numeric, dropdown,
        %   multiselect, or checkbox.
        %   scope is optional and may be either 'interface' or 'module'.
        %   Module-scoped options represent one value per Module owned by
        %   the interface instance.
        %   allowScalarExpansion is optional and, when true, allows a
        %   single module-scoped value to be applied to every module.
        %   getFile is optional and, when true, indicates the GUI should
        %   provide a file picker backed by uigetfile for that option.
        %   getFolder is optional and, when true, indicates the GUI should
        %   provide a folder picker backed by uigetdir for that option.
        %   fileFilter and fileDialogTitle are optional picker settings
        %   used when getFile or getFolder are enabled.
        spec = getCreationSpec()
    end



    methods
        % add_parameter - Create, initialize, and append a hw.Parameter to this Module
        function P = add_parameter(obj, name, value, options)
            % P = obj.add_parameter(name, value)
            % P = obj.add_parameter(name, value, Name=Value)
            % Create, initialize, and append a hw.Parameter to the module.
            %
            % Parameters
            %   name    - Display name for the new parameter (char).
            %   value   - Initial parameter value. String scalars are converted to char and force Type to 'String'.
            %   options - Name=Value pairs for hw.Parameter metadata (Description, Unit, Access, Type, Format, Visible, callback flags, UserData, isArray, isTrigger, isRandom, Min, Max).
            %
            % Returns
            %   P       - Created hw.Parameter handle.
            %
            % See also: documentation/hw/hw_Module.md, documentation/hw/hw_Parameter.md, hw.Parameter
            arguments
                obj
                name (1,:) char {mustBeText}
                value
                options.Description (1,1) string = ""
                options.Unit (1,:) char = ''
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','Read / Write'})} = 'Any'
                options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','File','Undefined'})} = 'Float'
                options.Format (1,:) char = '%g'
                options.Visible (1,1) logical = true
                options.PreUpdateFcnEnabled (1,1) logical = true
                options.EvaluatorFcnEnabled (1,1) logical = true
                options.PostUpdateFcnEnabled (1,1) logical = true
                options.UserData = []
                options.isArray (1,1) logical = false
                options.isTrigger (1,1) logical = false
                options.isRandom (1,1) logical = false
                options.Min (1,1) double = -inf
                options.Max (1,1) double = inf
            end
            copts = namedargs2cell(options);
            P = obj.Module.add_parameter(name, value, copts{:});
        end

        % all_parameters - Return all Parameters across all Modules, optionally filtered
        function P = all_parameters(obj, options)
            % P = all_parameters(obj, options)
            % Return all Parameters across all Modules, optionally filtered.
            %
            % Parameters:
            %   obj - hw.Interface. Hardware interface whose modules are queried.
            %   options.includeTriggers   - logical (default=true). Include trigger Parameters.
            %   options.includeInvisible  - logical (default=false). Include Parameters where Visible is false.
            %   options.includeArray      - logical (default=true). Include Parameters with array-valued contents.
            %   options.Access            - char (default='All'). Filter by access type: 'Read', 'Write', 'Any', or 'All'.
            %
            % Returns:
            %   P - hw.Parameter[]. Concatenated Parameters from every module after requested filters are applied.
            %
            % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Parameter.md
            arguments
                obj
                options.includeTriggers (1,1) logical = true
                options.includeInvisible (1,1) logical = false
                options.includeArray (1,1) logical = true
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','All','Read / Write'})} = 'All'
                options.asStruct (1,1) logical = false
            end
            P = [obj.Module(:).Parameters];
            if ~options.includeInvisible
                P=P([P.Visible]);
            end
            if ~options.includeTriggers
                P=P(~[P.isTrigger]);
            end
            if ~options.includeArray
                P=P(~[P.isArray]);
            end
            switch options.Access
                case 'Read'
                    P = P(~strcmp({P.Access}, 'Write'));
                case 'Write'
                    P = P(~strcmp({P.Access}, 'Read'));
                case {'Any', 'Read / Write'}
                    P = P(ismember({P.Access}, {'Any', 'Read / Write'}));
                otherwise
                    % no filtering needed
            end
            if options.asStruct
                P_ = struct();
                for k = 1:numel(P)
                    P_.(P(k).validName) = P(k);
                end
                P = P_;
            end

        end

        % filter_parameters - Filter Parameters by comparing a property to a target value
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
            %            Accepts both short names ('Param') and fully qualified
            %            names ('Module.Param').
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
            allP = obj.all_parameters(includeInvisible = options.includeInvisible);
            name = cellstr(name);

            % Build short and qualified name arrays for matching.
            % Qualified names have the form 'Module.Param'.
            shortNames = {allP.Name};
            qualNames  = arrayfun(@(p) [p.Module.Name '.' p.Name], allP, 'UniformOutput', false);

            result = hw.Parameter.empty(1, 0);
            for k = 1:numel(name)
                n = name{k};
                idx = find(strcmp(shortNames, n), 1);
                if isempty(idx)
                    idx = find(strcmp(qualNames, n), 1);
                end
                if ~isempty(idx)
                    result(end + 1) = allP(idx); %#ok<AGROW>
                elseif ~options.silenceParameterNotFound
                    vprintf(0, 1, 'Parameter "%s" was not found on any modules', n);
                end
            end

            if isempty(result)
                P = [];
            else
                P = result;
            end
        end
    end

    methods (Access = protected)
        function ensureUniqueParameterNames(obj)
            parameters = obj.all_parameters(includeInvisible = true, includeTriggers = true);
            if isempty(parameters)
                return
            end

            hardwareNames = arrayfun(@hw.Interface.getHardwareParameterName, parameters, 'UniformOutput', false);
            [uniqueNames, ~, groupIdx] = unique(hardwareNames, 'stable'); %#ok<ASGLU>
            counts = accumarray(groupIdx(:), 1);

            for paramIdx = 1:numel(parameters)
                if counts(groupIdx(paramIdx)) <= 1
                    continue
                end

                parameter = parameters(paramIdx);
                hardwareName = hardwareNames{paramIdx};
                parameter.Name = sprintf('%s[%d].%s', parameter.Module.Name, parameter.Module.Index, hardwareName);
            end
        end

        function setHardwareParameterName(~, parameter, hardwareName)
            if isempty(parameter.UserData) || ~isstruct(parameter.UserData)
                parameter.UserData = struct();
            end

            parameter.UserData.HardwareName = char(hardwareName);
        end
    end

    methods (Static)
        function name = getHardwareParameterName(parameter)
            name = parameter.Name;
            if isstruct(parameter.UserData) && isfield(parameter.UserData, 'HardwareName') && ~isempty(parameter.UserData.HardwareName)
                name = char(parameter.UserData.HardwareName);
            end
        end


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

    end
end
