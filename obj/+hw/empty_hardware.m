classdef (Hidden) empty_hardware < hw.Interface


    % properties (SetAccess = private)
    %     HW (1,:) matlab.mixin.Heterogeneous = hw.empty_hardware % Actual hardware interface object(s)
    % end


    properties (Constant)
        Type (1,1) string
    end


    properties (Dependent)
        status (1,:) char {mustBeMember(status,['undefined','idle','ready','running','error'])}
        statusMessage (1,:) char
    end

    properties
        mode (1,1) hw.DeviceState
    end

    methods (Access = protected)
        % setup hardware interface. this function must define obj.HW
        function setup_interface()
        end

        % close interface
        function close_interface()
        end

    end

    methods

        % trigger a hardware event
        function result = trigger(name)
            result = [];
        end

        % set new value to one or more hardware parameters
        % returns TRUE if successful, FALSE otherwise
        function result = set_parameter(name,value)
            result = [];
        end

        % read current value for one or more hardware parameters
        function value  = get_parameter(name)
            value = [];
        end

        function set_mode(mode)
        end


    end



end