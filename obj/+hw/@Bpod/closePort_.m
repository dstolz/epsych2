function closePort_(obj)
% closePort_(obj)
% Release the serial port handle. Safe to call when already closed.
%
% Never throws. It runs from close_interface and from delete, which are the
% same paths that force valves and PWM lines low, and an error raised here
% would abandon the rest of that teardown with outputs still energized.
%
% Transport level only: pump state (rxBuf_, matrixRunning_, the trial record)
% is not touched, because a test subclass replaces this file wholesale and
% would not clear it. close_interface owns that reset.
%
% Parameters:
%   obj - hw.Bpod instance.
%
% See also: hw.Bpod.openPort_, hw.Bpod.close_interface

if isempty(obj.HW)
    return
end

% Only a real handle can be deleted; a test subclass parks a plain struct in
% HW (the same case get.IsConnected guards with its isa check).
if isa(obj.HW, 'handle')
    if isvalid(obj.HW)
        try
            flush(obj.HW, 'input');
        catch ME
            % A yanked cable makes flush fail. Teardown continues regardless.
            vprintf(2, 'Bpod: input flush failed while closing %s: %s', ...
                obj.Port, ME.message);
        end
        delete(obj.HW);
    end
end

obj.HW = [];

vprintf(2, 'Bpod: released %s', obj.Port);
end
