classdef DeviceState < int8
    % Enumerated type representing device states
    enumeration
        Error   (-1)
        Idle    (0)
        Standby (1)
        Preview (2)
        Record  (3)
    end
end
