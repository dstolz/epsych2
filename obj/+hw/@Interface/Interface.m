classdef Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet
    % Abstract class for creating hardware interfaces for use by EPsych

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
            % P = find_parameter(obj,name)
            %
            % name can be a single char vector or a cellstr array
            %
            % Returns a handle to the hw.Parameter object(s). Can be
            % an array of Parameters if the same tag is found on multiple
            % modules
            %
            % options:
            %   silenceParameterNotFound    default = false
            %   includeInvisible            default = false
            %
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


        function P = filter_parameters(obj,propertyName,propertyValue,options,poptions)
            % P = obj.filter_parameters(propertyName,propertyValue,options)
            %
            % options:
            %   testFcn   default = @isequal
            %               other common functions:
            %                   @contains, @startsWith, etc.
            %   includeInvisible    default = false
            %
            % ex: P = obj.filter_parameters('Access','Read',testFcn=@contains)

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

            ind = arrayfun(@(a) options.testFcn(a.(propertyName),propertyValue),P);
            P = P(ind);
        end


        function P = all_parameters(obj,options)
            % P = all_parameters(obj,options)
            %
            % options:
            %   includeInvisible    default = false
            %   includeTriggers     default = true
            %   includeArray        default = true
            arguments
                obj
                options.includeTriggers (1,1) logical = true
                options.includeInvisible (1,1) logical = false
                options.includeArray (1,1) logical = true
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
        end

    end

end