classdef eventModeChange < event.EventData
    % ev = epsych.eventModeChange(newMode)
    % Event data for runtime mode transitions.
    %
    % Properties:
    %   NewMode - New device/runtime mode (typically a hw.DeviceState).
    properties
        NewMode
    end
    methods
        function obj = eventModeChange(newMode)
            if nargin>0
                obj.NewMode = newMode;
            end
        end
    end
end
