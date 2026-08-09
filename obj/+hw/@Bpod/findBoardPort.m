function port = findBoardPort(options)
% port = hw.Bpod.findBoardPort()
% port = hw.Bpod.findBoardPort(Name=Value)
% Scan available serial ports for a Bpod state machine.
%
% Opens each candidate, waits out the Arduino Due's native-USB re-enumeration,
% sends the '6' handshake, and accepts the port whose firmware answers with byte
% 53. Mirrors hw.Teensy.findBoardPort.
%
% Never throws: a port held by another process, a port with something else on
% the other end, and a machine with no serial ports at all all resolve to ''.
% That matters because this runs unattended at connect time and in headless
% smoke tests with no hardware present.
%
% Name=Value
%   Timeout (double)   - Per-port reply timeout (s). Default 1
%   BootDelay (double) - Settle time after opening a candidate (s). Default 1.5
%
% Returns:
%   port - Matching port name, or '' when none answered.
%
% See also: documentation/hw/hw_Bpod.md, hw.Bpod.setup_interface
arguments
    options.Timeout (1,1) double = 1
    options.BootDelay (1,1) double = 1.5
end

port = '';

% serialportlist itself throws when the serial support is unavailable, which is
% a "no board here" answer, not an error worth propagating to a session.
try
    candidates = cellstr(serialportlist("available"));
catch
    candidates = {};
end

for i = 1:numel(candidates)
    if local_probe(candidates{i}, options.Timeout, options.BootDelay)
        port = candidates{i};
        return
    end
end

end


function tf = local_probe(portName, timeout, bootDelay)
% tf = local_probe(portName, timeout, bootDelay)
% True when the device on portName answers the '6' handshake with byte 53.
% Always releases the probe port, and never throws.
tf = false;
sp = [];

try
    sp = serialport(portName, hw.Bpod.BAUD_RATE, Timeout = timeout);
    flush(sp, 'input');

    % The Due re-enumerates when the port opens; bytes written during that
    % window are lost, so a board probed too eagerly reads as "not a Bpod".
    pause(bootDelay);
    flush(sp, 'input');

    write(sp, uint8('6'), 'uint8');
    reply = local_readByte(sp, timeout);
    tf = ~isempty(reply) && reply(1) == 53;

    if tf
        % Courtesy: 'Z' returns the board to its disconnected state (LED off,
        % ConnectedToClient cleared) so it is in the same condition the real
        % connect expects. Its one-byte reply is read only to consume it.
        write(sp, uint8('Z'), 'uint8');
        local_readByte(sp, min(timeout, 0.25));
    end
catch
    % Port busy, no device, or a device that speaks something else. Either way
    % it is not our board.
end

try
    if ~isempty(sp) && isvalid(sp)
        delete(sp);
    end
catch
end

end


function b = local_readByte(sp, timeout)
% b = local_readByte(sp, timeout)
% Read one byte within timeout seconds, or return empty.
%
% Polls NumBytesAvailable rather than calling read() directly: read() warns on a
% short read, and a probe sweep across a machine's dead ports would otherwise
% fill the command window with warnings.
b = uint8([]);
t = tic;
while toc(t) < timeout
    if sp.NumBytesAvailable >= 1
        b = uint8(read(sp, 1, 'uint8'));
        return
    end
    pause(0.01);
end
end
