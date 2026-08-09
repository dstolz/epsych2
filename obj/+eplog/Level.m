classdef Level < int32
% eplog.Level  Named verbosity levels for the EPsych logger.
%
% The numeric values match the levels already used throughout EPsych, so a
% Level may be passed anywhere a numeric level is accepted:
%
%   vprintf(eplog.Level.Debug, 'connected to %s', name)
%   double(eplog.Level.Debug)   % 2
%
% Levels outside this set remain legal -- pass a plain number. Level 4 has a
% member here because the codebase already uses it in trial-loop traces.
%
% See also: vprintf, eplog.Logger, eplog.isEnabled

    enumeration
        LogOnly  (-1)   % written to the log only, never echoed to the console
        Critical ( 0)
        Info     ( 1)
        Debug    ( 2)
        Verbose  ( 3)
        Trace    ( 4)
    end

    methods (Static)
        function s = label(value)
            % s = eplog.Level.label(value)
            % Short name for any numeric level, including levels with no
            % enumeration member. Never errors -- it is used while logging.
            if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
                s = "L?";
                return
            end
            switch double(value)
                case -1, s = "LogOnly";
                case  0, s = "Critical";
                case  1, s = "Info";
                case  2, s = "Debug";
                case  3, s = "Verbose";
                case  4, s = "Trace";
                otherwise, s = "L" + string(double(value));
            end
        end
    end
end
