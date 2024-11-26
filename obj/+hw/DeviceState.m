classdef DeviceState < uint8
    % Enumerated type representing device states
    enumeration
        Error (0)
        Idle (1)
        Standby (2)
        Preview (3)
        Record (4)
    end
end
