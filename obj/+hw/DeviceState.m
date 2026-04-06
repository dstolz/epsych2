classdef DeviceState < int8
    % hw.DeviceState
    % Enumerated device-state values used by hw.Interface implementations.
    %
    % Members
    %   Idle, Standby, Preview, Record, Stop, Pause, Error
    %
    % Methods
    %   asString - Return the enumeration name as a string scalar.
    %   isIdle - True for terminal or inactive states.
    %
    % See also: documentation/hw/hw_Interface.md, hw.Interface
    enumeration
        Idle    (0)
        Standby (1)
        Preview (2)
        Record  (3)
        Stop    (4)
        Pause   (5)
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

