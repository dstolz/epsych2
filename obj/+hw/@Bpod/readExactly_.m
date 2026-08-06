function b = readExactly_(obj, n, timeout)
% b = readExactly_(obj, n, timeout)
% Block for up to timeout seconds waiting for exactly n bytes.
%
% Legal ONLY at connect and upload time, when the host has just issued a
% command and nothing else is on the wire: the '6' handshake, 'F', 'Z' and the
% single acknowledgement byte after a 'P' state-matrix upload. It must never
% be called once a matrix is running. After 'R' the device streams framed
% messages unsolicited, so blocking here would both stall the timer callback
% and consume bytes the pump is responsible for parsing.
%
% Waits by polling the buffered count rather than by handing the deadline to
% the serialport read, so the timeout is per call and independent of the
% port's own Timeout, and so a short reply never triggers the driver's own
% partial-read warning. The poll never yields the event queue: see the note on
% the wait loop below.
%
% On timeout the partial reply is drained and empty is returned, which keeps a
% half-arrived answer from being mistaken for the front of the next one. Bytes
% that arrive later still cannot be predicted, so a caller that intends to
% retry after a timeout should flushInput_ first.
%
% Parameters:
%   obj     - hw.Bpod instance.
%   n       - Exact number of bytes required.
%   timeout - Seconds to wait. Default obj.Timeout.
%
% Returns:
%   b - uint8 row vector of exactly n bytes, or empty on timeout or when the
%       link is down.
%
% See also: hw.Bpod.readNow_, hw.Bpod.setup_interface, hw.Bpod.sendStateMatrix

arguments
    obj
    n (1,1) double {mustBeNonnegative, mustBeInteger}
    timeout (1,1) double {mustBeNonnegative} = obj.Timeout
end

b = uint8([]);

if n < 1
    return
end

if isempty(obj.HW)
    % Short-circuit rather than burn the full timeout: offline parameter I/O
    % and serialization round-trips go through this path.
    vprintf(2, 'Bpod: readExactly_(%d) on a closed link; returning empty', n);
    return
end

t0 = tic;
while obj.bytesAvailable_() < n
    if toc(t0) >= timeout
        partial = obj.readNow_(n);
        vprintf(0, 1, ['Bpod: timed out after %g s waiting for %d byte(s) from %s ' ...
            '(%d arrived and were discarded)'], timeout, n, obj.Port, numel(partial));
        return
    end
    % Deliberately a tight spin: no pause, no drawnow. Yielding here would let
    % a queued timer tick run get.mode -> pump, and the pump would consume the
    % very reply this call is waiting for. sendStateMatrix runs inside the
    % timer callback, so that window is real. The spin is bounded by timeout
    % and only ever happens at connect or upload time.
end

b = obj.readNow_(n);

if numel(b) ~= n
    % The count was promised and then not delivered: the handle died between
    % the poll and the read. Treat it as a timeout rather than return a runt.
    vprintf(0, 1, 'Bpod: short read from %s: wanted %d byte(s), got %d', ...
        obj.Port, n, numel(b));
    b = uint8([]);
end
end
