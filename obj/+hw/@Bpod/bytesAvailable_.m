function n = bytesAvailable_(obj)
% n = bytesAvailable_(obj)
% Number of bytes waiting in the input buffer. 0 when the link is down.
%
% Sits in the hot path: get.mode runs the pump on every 10 ms tick of the
% session timer and the pump starts here, so this must be cheap and must never
% throw. An unplugged board reports 0 and the session keeps running until the
% epilogue watchdog or the trial ceiling decides otherwise.
%
% Parameters:
%   obj - hw.Bpod instance.
%
% Returns:
%   n - Non-negative scalar double count of buffered bytes.
%
% See also: hw.Bpod.readNow_, hw.Bpod.pump

n = 0;

if isempty(obj.HW)
    return
end

try
    n = double(obj.HW.NumBytesAvailable);
catch ME
    % Unplugging the USB cable invalidates the handle. Level 2 keeps a dead
    % link from writing one log line per tick at the default verbosity.
    vprintf(2, 'Bpod: cannot read NumBytesAvailable on %s: %s', obj.Port, ME.message);
    n = 0;
    return
end

if ~isscalar(n) || ~isfinite(n) || n < 0
    n = 0;
end
end
