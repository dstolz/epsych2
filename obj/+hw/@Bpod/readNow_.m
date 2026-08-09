function b = readNow_(obj, n)
% b = readNow_(obj, n)
% Read up to n bytes that are ALREADY buffered. Never blocks.
%
% This is what makes the byte pump resumable. After 'R' the device is a push
% stream driven by its own 100 us ISR, so a message can be split across timer
% ticks; the pump takes whatever has landed, parses greedily from the front of
% rxBuf_, and returns the moment a partial message is at the head. Nothing in
% the runtime is ever allowed to wait on the device, so this call must return
% within microseconds no matter what the board is doing.
%
% Only ever asks for bytes the driver has already reported, which is why the
% underlying read cannot hit its timeout: the buffered count only grows
% between the query and the read, it never shrinks.
%
% Parameters:
%   obj - hw.Bpod instance.
%   n   - Maximum number of bytes to take. Default inf, meaning everything
%         currently buffered.
%
% Returns:
%   b - uint8 row vector, possibly shorter than n and possibly empty. Empty
%       when the link is down, so an offline interface reads as "no traffic"
%       rather than throwing.
%
% See also: hw.Bpod.pump, hw.Bpod.bytesAvailable_, hw.Bpod.readExactly_

arguments
    obj
    n (1,1) double {mustBeNonnegative} = inf
end

b = uint8([]);

if n < 1
    return
end

k = min(floor(n), obj.bytesAvailable_());
if k < 1
    return
end

try
    raw = read(obj.HW, k, 'uint8');
catch ME
    % A dead handle reports bytes and then refuses to hand them over. Level 2
    % so an unplugged board does not write one log line per 10 ms tick.
    vprintf(2, 'Bpod: read of %d byte(s) from %s failed: %s', k, obj.Port, ME.message);
    return
end

b = reshape(uint8(raw), 1, []);
end
