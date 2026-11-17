function u = newUUID()
% u = epsych.newUUID()
% A random (version 4) UUID, lower case: 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.
%
% For identities that leave this computer -- a session's SessionUID names the
% same session in every copy of its file, and in the lab's subject registry --
% where epsych.SubjectRoster.newId's readable timestamp ids are not enough.
%
% Three constraints decide the source. java.util.UUID is out, as for newId,
% because Java is being removed from MATLAB. The global random stream is out
% because a trial selector may be drawing from it, and a session's sequence
% must not depend on how many ids were minted before it. So the bits come
% from tempname, whose documented unique name is an RFC 4122 v4 UUID from the
% operating system's generator (verified R2024b: version nibble 4, variant
% 8-b); its version and variant bits are set again here regardless. Should a
% release ever change that name's form, a private RandStream -- seeded from
% the clock, the process id and the CPU tick counter, never the global
% stream -- takes over.
%
% Returns:
%   u - (1,1) string.
%
% See also: epsych.SubjectRoster.newId, tempname

[~, name] = fileparts(tempname);
hex = lower(regexprep(char(name), '^tp', ''));
hex = strrep(hex, '_', '');
hex = strrep(hex, '-', '');
if numel(hex) ~= 32 || any(~ismember(hex, '0123456789abcdef'))
    hex = localPrivateHex();
end

hex(13) = '4';                                   % version 4
hex(17) = dec2hex(bitor(bitand(hex2dec(hex(17)), 3), 8), 1);  % variant 10xx
hex = lower(hex);
u = string([hex(1:8) '-' hex(9:12) '-' hex(13:16) '-' hex(17:20) '-' hex(21:32)]);
end

% -----------------------------------------------------------------------
function hex = localPrivateHex()
persistent stream
if isempty(stream)
    seed = mod(double(tic) + feature('getpid') * 7919 + ...
        floor(mod(posixtime(datetime('now')), 1) * 1e6), 2^32);
    stream = RandStream('mlfg6331_64', 'Seed', seed);
end
hex = lower(reshape(dec2hex(randi(stream, [0 15], 1, 32), 1)', 1, []));
end
