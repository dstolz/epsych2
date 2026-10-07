function h = hex8(txt)
% h = behavior.hex8(txt)
% Eight hex digits naming a piece of text: FNV-1a, 32 bit, over its UTF-8 bytes.
%
% Cache file names and settings hashes have to come out the same on every
% machine a dataset is opened on, which rules out anything seeded per session
% (MATLAB's own hashing) or dependent on the platform's text encoding.
%
% Parameters:
%   txt - Text (char or string scalar). Hashed exactly as given: lower it
%         first for a case-insensitive name.
%
% Returns:
%   h - 1x1 string of eight lowercase hex digits, e.g. "811c9dc5" for "".
%
% Example:
%   behavior.hex8("foobar")     % "bf9cf968"
%
% See also: behavior.Catalog

arguments
    txt (1,:) char
end

bytes = double(unicode2native(txt, 'UTF-8'));

% The FNV prime is 2^24 + 403. Multiplying in one step would pass 2^53 and lose
% the low bits a double carries, so the product is taken in two exact halves:
% the 2^24 part as a uint32 shift (whose overflow is exactly the mod 2^32), the
% 403 part in double (< 2^41).
h = 2166136261;
for b = bytes
    h = double(bitxor(uint32(h), uint32(b)));
    h = mod(double(bitshift(uint32(h), 24)) + h * 403, 2^32);
end

h = string(sprintf('%08x', h));

end
