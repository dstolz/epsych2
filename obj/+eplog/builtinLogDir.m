function d = builtinLogDir()
% d = eplog.builtinLogDir()
% The log directory EPsych uses when no override is configured:
% <epsych root>/.error_logs. The directory ships with the clone as a
% .gitignore stub that excludes every log written into it, so the default
% costs the working tree nothing.
%
% Separate from eplog.defaultLogDir so callers can name the fallback while an
% override is in force -- the Customize dialog shows it as placeholder text in
% an empty Error Log Path field, which is exactly the moment the override is
% about to be cleared.
%
% epsych_path derives the root from "which", so it returns '' when the repo is
% not on the MATLAB path. fullfile('', '.error_logs') is a RELATIVE path, which
% would scatter log directories through whatever folder happened to be the
% working directory. Falling back to tempdir keeps logging predictable, and is
% also why a relative override is refused rather than resolved against cd.
%
% Returns:
%   d - absolute path to the built-in log directory (not created here)
%
% See also: eplog.defaultLogDir, eplog.setLogDir, epsych_path

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
