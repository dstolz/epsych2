classdef EventHub < handle
    % h = epsych.EventHub()
    % Event broadcaster shared by the components of one session.
    %
    % The runtime owns one of these (epsych.Runtime.EVENTS) and every GUI,
    % psychophysics object, and trial selector that needs to know about a
    % trial listens to it rather than polling.
    %
    % Was named epsych.Helper until 2026-08; the old name said nothing about
    % what the class does and collided with the unrelated gui.Helper.
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
