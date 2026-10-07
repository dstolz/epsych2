classdef StudyEvent < event.EventData
    % ev = behavior.StudyEvent(message)
    % Payload of behavior.Study's Busy event: what the study is doing, or ""
    % when it has finished, so a window can show one status line without
    % knowing which method is running.
    %
    % Properties:
    %   Message - text for a status line; "" means idle again.

    properties
        Message (1,1) string = ""
    end

    methods
        function ev = StudyEvent(message)
            arguments
                message (1,1) string = ""
            end
            ev.Message = message;
        end
    end
end
