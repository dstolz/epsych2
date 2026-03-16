classdef ModeChangeEvent < event.EventData
    % ev = epsych.ModeChangeEvent(newMode)
    % Event data for runtime mode transitions.
    %
    % Properties:
    %   NewMode - New device/runtime mode (typically a hw.DeviceState).
    properties
        NewMode
    end
    methods
        function obj = ModeChangeEvent(newMode)
            if nargin>0
                obj.NewMode = newMode;
            end
        end
    end
end
