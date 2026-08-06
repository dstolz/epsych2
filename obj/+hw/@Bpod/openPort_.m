function openPort_(obj)
% openPort_(obj)
% Open the serial port to the Bpod state machine.
%
% One of the seven files that touch the serialport object. Everything else in
% this class speaks the firmware protocol through this seam, so tmp/Bpod_Mock
% can simulate an Arduino Due by replacing these files and nothing else.
%
% The link is raw binary and deliberately has no terminator configured: the
% firmware frames its own messages as [1 nEvents ev...] and answers 'I', 'F'
% and 'P' with a single bare byte, so any line discipline would eat or split
% payload bytes. Baud comes from the class constant rather than a property
% because it is fixed by the firmware's SerialUSB and a rig must not be able
% to mistune it.
%
% Does not wait out the board's boot: the Due re-enumerates when the port
% opens, and setup_interface owns that pause (obj.BootDelay) so the delay is
% skipped entirely by a test subclass.
%
% Parameters:
%   obj - hw.Bpod instance whose Port is already resolved.
%
% See also: hw.Bpod.closePort_, hw.Bpod.setup_interface,
%           documentation/hw/hw_Bpod.md

if isempty(obj.Port)
    error('hw:Bpod:NoPort', ...
        ['No serial port is set for this hw.Bpod interface. Construct it with a ' ...
         'port name (hw.Bpod(''COM3'')) or with AutoDetect=true.']);
end

% Opening on top of a live handle would leak the OS handle and leave the
% device held open by a process nothing points at any more.
obj.closePort_();

% Lets serialport throw: a port that is missing or held by another process is
% a connect-time failure the caller must see, not something to degrade past.
obj.HW = serialport(obj.Port, hw.Bpod.BAUD_RATE, Timeout = obj.Timeout);

% Anything already buffered predates this session and belongs to whatever
% spoke to the board last, including a matrix aborted by a previous crash.
flush(obj.HW, 'input');

vprintf(2, 'Bpod: opened %s at %d baud (timeout %g s)', ...
    obj.Port, hw.Bpod.BAUD_RATE, obj.Timeout);
end
