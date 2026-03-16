classdef Helper < handle
    % h = epsych.Helper()
    % Lightweight event broadcaster used by EPsych components.
    %
    % This helper defines common runtime events that can be listened to by
    % GUIs and protocol controllers.
    %
    % Events:
    %   NewData, NewTrial, ModeChange
    %
    % Methods:
    %   valid_psych_obj - Validate that an object is in the psychophysics package.
    

    properties

    end

    events (ListenAccess = 'public', NotifyAccess = 'public')
        % eventually move these to a Runtime object, once it's built
        NewData
        NewTrial
        ModeChange
    end

    methods
        
        
    end
    
    methods (Static)
        function tf = valid_psych_obj(obj)
            tf = isobject(obj);
            if ~tf, return; end
            c = class(obj);
            tf = isequal(c(1:find(c=='.')-1),'psychophysics');
        end

    end

end