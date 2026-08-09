function d = defaultLogDir()
% d = eplog.defaultLogDir()
% Directory the daily log files are written to.
%
% Resolves in this order:
%   1. The configured override, getpref('eplog','LogDir') -- set from RunExpt's
%      Customize > Paths > Error Log Path, or programmatically through
%      eplog.setLogDir. Rigs whose repository lives on a read-only or synced
%      share need the logs somewhere else.
%   2. <epsych root>/.error_logs, the built-in default, matching where EPsych
%      has always written. The directory ships with the clone as a .gitignore
%      stub that excludes every log written into it, so the default costs the
%      working tree nothing.
%
% epsych_path derives the root from "which", so it returns '' when the repo is
% not on the MATLAB path. fullfile('', '.error_logs') is a RELATIVE path, which
% would scatter log directories through whatever folder happened to be the
% working directory. Falling back to tempdir keeps logging predictable, and is
% also why a relative override is refused rather than resolved against cd.
%
% Returns:
%   d - absolute path to the log directory (not created here)
%
% See also: eplog.setLogDir, eplog.sink.FileSink, epsych_path

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

% A stored relative path is worse than no override at all -- see above.
if ~isempty(d) && eplog.isAbsolutePath(d)
    return
end

root = '';
try
    root = epsych_path;
catch
    % epsych_path not on the path yet; fall through to tempdir.
end

if isempty(root) || ~ischar(root) || ~isfolder(root)
    root = tempdir;
end

d = fullfile(root,'.error_logs');
end
