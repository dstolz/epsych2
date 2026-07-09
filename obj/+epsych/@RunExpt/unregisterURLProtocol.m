function ok = unregisterURLProtocol()
% ok = epsych.RunExpt.unregisterURLProtocol()
% Remove the "epsych://" URL protocol registration for the current Windows
% user (the HKCU\Software\Classes\epsych key), regardless of which handler it
% currently points to.
%
% Returns:
%   ok - true if the registration was removed (or was already absent).
%
% See also: epsych.RunExpt.registerURLProtocol, epsych.RunExpt.isURLProtocolRegistered

ok = false;

if ~ispc
    vprintf(0,1,'The epsych:// URL protocol only exists on Windows.');
    return
end

key = 'HKCU\Software\Classes\epsych';

% If the key does not exist there is nothing to remove.
if system(['reg query "' key '"']) ~= 0
    ok = true;
    return
end

[status, out] = system(['reg delete "' key '" /f']);
if status ~= 0
    vprintf(0,1,'Failed to remove epsych:// protocol registration: %s', strtrim(out));
    return
end

vprintf(1,'Removed epsych:// URL protocol registration.');
ok = true;
