classdef (Hidden) modeEvent < event.EventData
    properties
        mode
        oldMode
    end
    
    methods
        function obj = modeEvent(data)
            obj.mode = data.mode;
            obj.oldMode = data.oldMode;
        end
    end
end
