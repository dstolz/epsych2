function d = defaultLogDir()
% d = eplog.defaultLogDir()
% Directory the daily log files are written to.
%
% Resolves in this order:
%   1. The configured override, getpref('eplog','LogDir') -- set from RunExpt's
%      Customize > Paths > Error Log Path, or programmatically through
%      eplog.setLogDir. Rigs whose repository lives on a read-only or synced
%      share need the logs somewhere else.
%   2. eplog.builtinLogDir, <epsych root>/.error_logs, matching where EPsych
%      has always written.
%
% Returns:
%   d - absolute path to the log directory (not created here)
%
% See also: eplog.builtinLogDir, eplog.setLogDir, eplog.sink.FileSink

d = '';
try
    % ispref first: the three-argument getpref CREATES the preference when it
    % is missing, so querying with a default would write an empty LogDir into
    % the preferences file on every sink construction and leave "is there an
    % override?" unanswerable.
    if ispref('eplog','LogDir')
        d = char(getpref('eplog','LogDir'));
    end
catch
    % Preferences unreadable (rare, but getpref touches the file system);
    % fall through to the built-in default rather than losing logging.
end

% A stored relative path is worse than no override at all: it would follow the
% working directory, so it is discarded rather than resolved against cd.
if ~isempty(d) && eplog.isAbsolutePath(d)
    return
end

d = eplog.builtinLogDir();
end
