classdef Interface < matlab.mixin.Heterogeneous & matlab.mixin.SetGet
    % Abstract class for creating hardware interfaces for use by EPsych

    properties (Abstract,SetAccess = protected)
        % HW (1,:) matlab.mixin.Heterogeneous % Actual hardware interface object(s)

        Module (1,:) hw.Module
        nModules (1,1) uint8
    end

    properties (Abstract,Constant)
        Type (1,1) string
    end

    properties (Abstract,SetObservable)
        mode (1,1) hw.DeviceState
    end

    properties (Abstract,Dependent)
        status (1,:) char {mustBeMember(status,['undefined','idle','ready','running','error'])}
        statusMessage (1,:) char
    end

    properties (Abstract)
       ExperimentInfo (1,1) % custom structure
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


        set_mode(mode)


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
            arguments
                obj
                name 
                options.includeInvisible (1,1) logical = false
                options.silenceParamterNotFound (1,1) logical = false
            end

            P = obj.all_parameters(includeInvisible = options.includeInvisible);

            name = cellstr(name);

            ind = ismember({P.Name},name);

            if any(ind)
                P = P(ind);
            elseif ~options.silenceParamterNotFound
                cellfun(@(a) vprintf(0,1,'Parameter "%s" was not found on any modules',a),name)
                P = [];
            end
        end


        function P = filter_parameters(obj,propertyName,propertyValue,options)
            % P = obj.filter_parameters(propertyName,propertyValue,options)
            % 
            % options:
            %   testFcn   default = @isequal
            %               other common functions:
            %                   @contains, @startsWith, etc.
            %
            % ex: P = obj.filter_parameters('Access','Read',testFcn=@contains)
            
            arguments
                obj
                propertyName (1,:) char
                propertyValue
                options.testFcn (1,1) function_handle = @isequal
                options.includeInvisible (1,1) logical = false
            end

            P = obj.all_parameters(includeInvisible = options.includeInvisible);

            ind = arrayfun(@(a) options.testFcn(a.(propertyName),propertyValue),P);
            P = P(ind);
        end


        function P = all_parameters(obj,options)
            arguments
                obj
                options.includeInvisible (1,1) logical = false
            end

            P = [obj.Module(:).Parameters];

            if ~options.includeInvisible
                P=P([P.Visible]);
            end
        end
    end

end