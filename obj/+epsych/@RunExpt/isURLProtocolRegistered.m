function tf = isURLProtocolRegistered()
% tf = epsych.RunExpt.isURLProtocolRegistered()
% True if the "epsych://" protocol is registered for the current Windows user
% AND its handler command points to this repository's handler script. A stale
% registration (pointing at a different/old location) returns false so the
% caller can offer to re-register.
%
% See also: epsych.RunExpt.registerURLProtocol, epsych.RunExpt.unregisterURLProtocol

tf = false;

if ~ispc, return, end

handler = epsych.RunExpt.urlHandlerPath;
if strlength(handler) == 0, return, end

[status, out] = system('reg query "HKCU\Software\Classes\epsych\shell\open\command" /ve');
if status ~= 0, return, end

tf = contains(string(out), handler, 'IgnoreCase', true);
