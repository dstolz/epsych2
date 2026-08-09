function d = defaultLogDir()
% d = eplog.defaultLogDir()
% Directory the daily log files are written to.
%
% Resolves to <epsych root>/.error_logs, matching where EPsych has always
% written and where RunExpt's "Open Current Error Log", the SelfTest log check
% and SelfTest.saveReport all look.
%
% epsych_path derives the root from "which", so it returns '' when the repo is
% not on the MATLAB path. fullfile('', '.error_logs') is a RELATIVE path, which
% would scatter log directories through whatever folder happened to be the
% working directory. Falling back to tempdir keeps logging predictable.
%
% Returns:
%   d - absolute path to the log directory (not created here)
%
% See also: eplog.sink.FileSink, epsych_path

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
