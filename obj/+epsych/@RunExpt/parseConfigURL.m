function configPath = parseConfigURL(url)
% configPath = epsych.RunExpt.parseConfigURL(url)
% Decode the configuration file path from an "epsych://" link built by
% epsych.RunExpt.buildConfigURL.
%
% Parameters:
%   url - An "epsych://load?config=<base64url>" link (string or char). Any
%         trailing slash or whitespace the OS may append is ignored.
%
% Returns:
%   configPath - The decoded absolute file path as a string, or "" if the
%                link does not contain a config token.
%
% See also: epsych.RunExpt.buildConfigURL, epsych.RunExpt.handleConfigLink
arguments
    url (1,1) string
end

configPath = "";

% Extract the base64url token following "config=". base64url uses only
% [A-Za-z0-9-_], so this naturally stops at any trailing slash/space.
tok = regexp(char(url), 'config=([A-Za-z0-9\-_]+)', 'tokens', 'once');
if isempty(tok), return, end
b64 = tok{1};

% Restore standard base64 alphabet and padding.
b64 = strrep(b64, '-', '+');
b64 = strrep(b64, '_', '/');
padLen = mod(4 - mod(numel(b64), 4), 4);
b64 = [b64 repmat('=', 1, padLen)];

bytes = matlab.net.base64decode(b64);
configPath = string(native2unicode(uint8(bytes(:)'), 'UTF-8'));
