classdef Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet
    % hw.Interface
    %
    % Abstract base class for creating hardware interfaces used by EPsych.
    % Implementations provide a set of Modules and expose Parameters that can
    % be queried/modified in a uniform way.
    %
    % Usage:
    %   % Concrete subclasses implement setup/close and parameter I/O
    %   I = MyInterfaceSubclass(...);
    %   P = I.find_parameter("Reward");
    %   ok = I.set_parameter("Reward", 1);

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

        function P = find_parameter(obj,name,options)
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = false
                options.silenceParameterNotFound (1,1) logical = false
            end

            % P = find_parameter(obj,name)
            % P = find_parameter(obj,name, includeInvisible=..., silenceParameterNotFound=...)
            %
            % Return handle(s) to matching hw.Parameter objects by Name.
            % If the same Name exists on multiple modules, P can be an array.
            %
            % Parameters
            %   name: char | string | cellstr
            %       Parameter name(s) to search for.
            %   includeInvisible: logical (default=false)
            %       Include Parameters where Visible is false.
            %   silenceParameterNotFound: logical (default=false)
            %       Suppress warning output if nothing is found.
            %
            % Returns
            %   P: hw.Parameter[]
            %       Matching Parameter handle(s). Empty if not found.

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


        function P = filter_parameters(obj,propertyName,propertyValue,options,poptions)
            arguments
                obj
                propertyName (1,:) char
                propertyValue
                options.testFcn (1,1) function_handle = @isequal
                poptions.includeTriggers (1,1) logical = false
                poptions.includeInvisible (1,1) logical = false
            end

            % P = filter_parameters(obj,propertyName,propertyValue)
            % P = filter_parameters(obj,propertyName,propertyValue, testFcn=..., includeTriggers=..., includeInvisible=...)
            %
            % Filter Parameters by comparing a property to a target value.
            %
            % Parameters
            %   propertyName: char
            %       Name of the hw.Parameter property to test (e.g. 'Access').
            %   propertyValue: any
            %       Target value/pattern passed to the test function.
            %   testFcn: function_handle (default=@isequal)
            %       Comparator function, e.g. @contains, @startsWith.
            %   includeTriggers: logical (default=false)
            %       Include trigger Parameters.
            %   includeInvisible: logical (default=false)
            %       Include Parameters where Visible is false.
            %
            % Returns
            %   P: hw.Parameter[]
            %       Parameters matching the filter criteria.

            poptions = namedargs2cell(poptions);
            P = obj.all_parameters(poptions{:});

            % normalize testFcn output to a logical scalar
            ind = arrayfun(@(a) obj.local_test(options.testFcn, a.(propertyName), propertyValue), P);
            P = P(ind);
        end


        function P = all_parameters(obj,options)
            arguments
                obj
                options.includeTriggers (1,1) logical = true
                options.includeInvisible (1,1) logical = false
                options.includeArray (1,1) logical = true
            end

            % P = all_parameters(obj)
            % P = all_parameters(obj, includeTriggers=..., includeInvisible=..., includeArray=...)
            %
            % Return all Parameters across all Modules, optionally filtered.
            %
            % Parameters
            %   includeTriggers: logical (default=true)
            %       Include trigger Parameters.
            %   includeInvisible: logical (default=false)
            %       Include Parameters where Visible is false.
            %   includeArray: logical (default=true)
            %       Include array-valued Parameters.
            %
            % Returns
            %   P: hw.Parameter[]
            %       Concatenated Parameters from all modules.

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
        end

    end

    methods (Static)


        function tf = local_test(fcn, val, pat)
            % tf = local_test(fcn,val,pat)
            %
            % Normalize the output of a comparison function to a logical
            % scalar for filtering operations.
            %
            % Parameters
            %   fcn: function_handle
            %       Comparison function, e.g. @isequal, @contains.
            %   val: any
            %       Value from the Parameter property.
            %   pat: any
            %       Pattern/target value passed to the comparison function.
            %
            % Returns
            %   tf: logical
            %       True if the comparison indicates a match.
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