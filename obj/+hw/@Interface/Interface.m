classdef Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet
    % hw.Interface
    % Abstract base class for EPsych hardware interfaces.
    %
    % Concrete subclasses define one or more hw.Module objects and expose
    % hw.Parameter instances through a uniform trigger/read/write API.
    % This lets GUIs, runtime code, and tests interact with different
    % hardware backends through the same interface contract.
    %
    % Example usage:
    %   I = hw.TDT_Synapse(...);
    %   P = I.find_parameter("Reward");
    %   ok = I.set_parameter("Reward", 1);
    %
    % Properties:
    %   Module - Array of hw.Module objects exposed by the interface.
    %   Type   - Constant identifier for the interface implementation.
    %   mode   - Current hw.DeviceState for the interface.
    %
    % Methods:
    %   all_parameters    - Return Parameters across all modules.
    %   find_parameter    - Resolve Parameters by name.
    %   filter_parameters - Filter Parameters by property value.
    %   setup_interface   - Allocate or connect backend resources (abstract).
    %   close_interface   - Release backend resources (abstract).
    %   trigger          - Issue a named hardware event (abstract).
    %   set_parameter    - Write one or more parameter values (abstract).
    %   get_parameter    - Read one or more parameter values (abstract).
    %
    % See also: documentation/hw_Interface.md, hw.Module, hw.Parameter

    properties (Abstract,SetAccess = protected)
        % HW (1,:) matlab.mixin.Heterogeneous % Actual hardware interface object(s)

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
        % setup hardware interface. this function must define obj.HW
        setup_interface()

        % close interface
        close_interface()

    end

    methods (Abstract)

        % trigger a hardware event
        result = trigger(name)

        % set new value to one or more hardware parameters
        % returns TRUE if successful, FALSE otherwise
        result = set_parameter(name,value)

        % read current value for one or more hardware parameters
        value  = get_parameter(name)

    end


    methods

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

                % return in original order
                [ind,idx] = ismember(name,{P.Name});
                P = P(idx(ind));
            else
                P = [];
                if ~options.silenceParameterNotFound
                    cellfun(@(a) vprintf(0,1,'Parameter "%s" was not found on any modules',a),name)
                end
            end


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

            % normalize testFcn output to a logical scalar
            ind = arrayfun(@(a) obj.local_test(options.testFcn, a.(propertyName), propertyValue), P);
            P = P(ind);
        end


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
            arguments
                obj
                options.includeTriggers (1,1) logical = true
                options.includeInvisible (1,1) logical = false
                options.includeArray (1,1) logical = true
                options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Read / Write','Any'})} = 'Any'
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

            % if Access filter is 'Read' or 'Read/Write', exclude Write-only parameters
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