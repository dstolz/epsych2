function flushInput_(obj)
% flushInput_(obj)
% Discard whatever is sitting in the input buffer.
%
% Transport level only: it does not touch rxBuf_ or any other pump state,
% because a test subclass replaces this file wholesale and would not know
% about them. A caller resyncing the protocol (close_interface, or the drain
% after an 'X' abort) must clear rxBuf_ itself.
%
% Never throws. It runs on the teardown and abort paths, where an error would
% leave the port open and the outputs energized.
%
% Parameters:
%   obj - hw.Bpod instance.
%
% See also: hw.Bpod.readNow_, hw.Bpod.abortMatrix, hw.Bpod.close_interface

if isempty(obj.HW)
    return
end

n = obj.bytesAvailable_();

try
    flush(obj.HW, 'input');
catch ME
    vprintf(2, 'Bpod: input flush on %s failed (%s); draining instead', ...
        obj.Port, ME.message);
    % Draining reaches the same end state on a handle that refuses flush, and
    % readNow_ swallows its own transport errors.
    obj.readNow_(inf);
end

if n > 0
    vprintf(2, 'Bpod: discarded %d buffered byte(s) on %s', n, obj.Port);
end
end
