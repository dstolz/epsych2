function ok = registerURLProtocol()
% ok = epsych.RunExpt.registerURLProtocol()
% Register the "epsych://" URL protocol for the current Windows user so that
% clicking an epsych:// link (e.g. from a Google Sheet) hands the URL to the
% RunExpt handler script. Writes under HKCU\Software\Classes so no
% administrator rights are required.
%
% The handler path is resolved from the current repository location, so
% re-run this after moving the EPsych folder.
%
% Returns:
%   ok - true if all registry writes succeeded.
%
% See also: epsych.RunExpt.unregisterURLProtocol,
%           epsych.RunExpt.isURLProtocolRegistered, epsych.RunExpt.handleConfigLink

ok = false;

if ~ispc
    vprintf(0,1,'The epsych:// URL protocol can only be registered on Windows.');
    return
end

handler = epsych.RunExpt.urlHandlerPath;
if strlength(handler) == 0
    vprintf(0,1,'Could not locate the epsych:// handler script; is EPsych on the MATLAB path?');
    return
end
if ~isfile(handler)
    vprintf(0,1,'Handler script not found at expected location: %s', handler);
    return
end

key = 'HKCU\Software\Classes\epsych';

% reg.exe /d escaping: the stored command value is
%   wscript.exe "<handler>" "%1"
% with each embedded quote escaped as \" inside the outer /d "..." quotes.
cmdVal = ['wscript.exe \"' char(handler) '\" \"%1\"'];

commands = { ...
    ['reg add "' key '" /ve /d "URL:EPsych Protocol" /f'], ...
    ['reg add "' key '" /v "URL Protocol" /t REG_SZ /d "" /f'], ...
    ['reg add "' key '\shell\open\command" /ve /d "' cmdVal '" /f'] };

for i = 1:numel(commands)
    [status, out] = system(commands{i});
    if status ~= 0
        vprintf(0,1,'Failed to register epsych:// protocol: %s', strtrim(out));
        return
    end
end

vprintf(1,'Registered epsych:// URL protocol -> %s', handler);
ok = true;
