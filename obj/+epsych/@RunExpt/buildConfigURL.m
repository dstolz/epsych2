function url = buildConfigURL(configPath)
% url = epsych.RunExpt.buildConfigURL(configPath)
% Build an "epsych://" link that, when clicked, loads configPath into a
% running RunExpt session (see epsych.RunExpt.handleConfigLink).
%
% The absolute file path is UTF-8 encoded and then base64url encoded so the
% link is safe to paste anywhere (drive colons, backslashes, spaces, and
% unicode are all escaped) and needs no further URL encoding.
%
% Parameters:
%   configPath - Full path to a .ecfg configuration file.
%
% Returns:
%   url - The "epsych://load?config=<base64url>" link as a string.
%
% See also: epsych.RunExpt.parseConfigURL, epsych.RunExpt.handleConfigLink
arguments
    configPath (1,1) string
end

bytes = unicode2native(char(configPath), 'UTF-8');
b64   = matlab.net.base64encode(bytes);

% Convert standard base64 to base64url and drop padding.
b64 = strrep(b64, '+', '-');
b64 = strrep(b64, '/', '_');
b64 = erase(b64, '=');

url = "epsych://load?config=" + string(b64);
