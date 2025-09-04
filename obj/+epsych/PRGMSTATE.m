classdef PRGMSTATE < int32
    % Program state enumeration for ep_RunExpt2
    %
    % Values extracted from current codebase (Ep Run Expt (updated Layout)):
    %   NOCONFIG, CONFIGLOADED, READY, RUNNING, POSTRUN, STOP, ERROR
    %
    % Numeric codes mirror existing STATEID usage:
    %   ERROR = -1, NOCONFIG = 0, CONFIGLOADED = 1, STOP = 2,
    %   READY = 3, RUNNING = 4, POSTRUN = 5

    enumeration
        ERROR       (-1)
        NOCONFIG    (0)
        CONFIGLOADED(1)
        STOP        (2)
        READY       (3)
        RUNNING     (4)
        POSTRUN     (5)
    end

    methods (Static)
        function e = fromString(s)
            % Convert legacy char/string labels to PRGMSTATE
            if isstring(s); s = char(s); end
            if ~ischar(s)
                error('PRGMSTATE:InvalidType','fromString expects char or string.');
            end
            switch upper(strtrim(s))
                case 'ERROR',        e = PRGMSTATE.ERROR;
                case 'NOCONFIG',     e = PRGMSTATE.NOCONFIG;
                case 'CONFIGLOADED', e = PRGMSTATE.CONFIGLOADED;
                case 'STOP',         e = PRGMSTATE.STOP;
                case 'READY',        e = PRGMSTATE.READY;
                case 'RUNNING',      e = PRGMSTATE.RUNNING;
                case 'POSTRUN',      e = PRGMSTATE.POSTRUN;
                otherwise
                    error('PRGMSTATE:InvalidString','Unknown state "%s".', s);
            end
        end
    end

    methods
        function s = asString(obj)
            % Return the enum name as a scalar string
            s = string(char(obj));
        end

        function tf = isTerminal(obj)
            % Helper: whether state is terminal
            tf = ismember(obj, [PRGMSTATE.ERROR, PRGMSTATE.STOP, PRGMSTATE.POSTRUN]);
        end
    end
end
