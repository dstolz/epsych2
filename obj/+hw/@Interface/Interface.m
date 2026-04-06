

classdef Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet
    % hw.Interface
    % Abstract base class for EPsych hardware interfaces.
    %
    % Provides a uniform API for interacting with hardware modules and parameters.
    % Concrete subclasses define one or more hw.Module objects and expose hw.Parameter
    % instances through trigger, read, and write methods. This enables GUIs, runtime code,
    % and tests to interact with different hardware backends using a consistent interface contract.
    %
    % Example:
    %   I = hw.TDT_Synapse(...);
    %   P = I.find_parameter("Reward");
    %   ok = I.set_parameter("Reward", 1);
    %
    % Properties:
    %   Module      - Array of hw.Module objects exposed by the interface.
    %   Type        - Constant identifier for the interface implementation.
    %   mode        - Current hw.DeviceState for the interface.
    %   h_listeners - Listeners for property or event changes.
    %
    % Methods:
    %   add_parameter     - Create and append a hw.Parameter to a module.
    %   all_parameters    - Return Parameters across all modules.
    %   filter_parameters - Filter Parameters by property value.
    %   find_parameter    - Resolve Parameters by name.
    %   setup_interface   - Allocate or connect backend resources (abstract).
    %   close_interface   - Release backend resources (abstract).
    %   trigger          - Issue a named hardware event (abstract).
    %   set_parameter    - Write one or more parameter values (abstract).
    %   get_parameter    - Read one or more parameter values (abstract).
    %
    % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Module.md,
    %   documentation/hw/hw_Parameter.md, hw.Module, hw.Parameter

    properties (Abstract,SetAccess = protected)
        Module (1,:) hw.Module
    end

    properties (Abstract,Constant)
        Type (1,1) string
    end

    properties (Abstract,SetObservable,AbortSet)
        mode (1,1) hw.DeviceState
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
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Read / Write'})} = 'Read / Write'
                options.Type (1,:) char {mustBeMember(options.Type,{'Float','Integer','Boolean','Buffer','Coefficient Buffer','String','Undefined'})} = 'Float'
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
            %   options.Access            - char (default='Any'). Filter by access type: 'Read', 'Write', 'Read / Write', or 'Any'.
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
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Read / Write','Any'})} = 'Any'
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
                case 'Read / Write'
                    P = P(strcmp({P.Access}, 'Read / Write'));
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

    end

end
