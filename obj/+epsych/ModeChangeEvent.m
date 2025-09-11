classdef ModeChangeEvent < event.EventData
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
