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
end
