classdef DeviceState < int8
    % Enumerated type representing device states
    enumeration
        Idle    (0)
        Standby (1)
        Preview (2)
        Record  (3)
        Stop    (4)
        Error   (-1)
    end

    methods 
        function s = asString(obj)
            % Return the enum name as a scalar string
            s = string(char(obj));
        end

        function tf = isIdle(obj)
            % Helper: whether state is terminal
            tf = ismember(obj, [DeviceState.Idle, DeviceState.Stop, DeviceState.Error]);
        end
    end
end
