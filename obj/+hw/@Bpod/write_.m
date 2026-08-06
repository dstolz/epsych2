function write_(obj, bytes)
% write_(obj, bytes)
% Write raw bytes to the state machine. Every outbound byte goes through here.
%
% Accepts char, so a caller can write the opcode literally ('6', 'OV', 'R'),
% or a numeric vector of byte values. Multi-byte values must already be split
% into bytes by the caller: this function only clamps, it does not serialize.
%
% Writing to a link that is down is a logged no-op rather than an error.
% Offline construction, protocol serialization round-trips and
% ProtocolDesigner all touch a disconnected interface, and a cable that comes
% loose mid-session must not throw out of a timer callback. The link state is
% deliberately NOT changed here on failure: close_interface and
% setup_interface own linkReady_, and silently clearing it would disarm the
% abortMatrix call in set.mode, which is the path that drives outputs low.
%
% Parameters:
%   obj   - hw.Bpod instance.
%   bytes - char row, string scalar, or numeric vector of byte values (0-255).
%
% See also: hw.Bpod.readNow_, hw.Bpod.readExactly_, hw.Bpod.flushInput_

if isempty(bytes)
    return
end

if ischar(bytes) || isstring(bytes)
    data = uint8(char(bytes));
else
    data = double(bytes);
    data = data(:).';
    bad = ~isfinite(data) | data < 0 | data > 255 | data ~= floor(data);
    if any(bad)
        % Silent saturation would put a wrong opcode or a truncated state
        % matrix on the wire, and the protocol carries no CRC, sequence
        % number or resync marker that could catch it downstream.
        vprintf(0, 1, ['Bpod: %d of %d outbound byte(s) are not integers in 0-255 ' ...
            'and will be clamped. Split multi-byte values before calling write_.'], ...
            sum(bad), numel(data));
    end
    data = uint8(data);
end
data = reshape(data, 1, []);

if ~obj.linkReady_ || isempty(obj.HW)
    vprintf(2, 'Bpod: dropped %d byte(s) written to a closed link', numel(data));
    return
end

try
    write(obj.HW, data, 'uint8');
catch ME
    vprintf(0, 1, 'Bpod: write of %d byte(s) to %s failed: %s', ...
        numel(data), obj.Port, ME.message);
end
end
