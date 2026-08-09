function setup_interface(obj)
% setup_interface(obj)
% Open the serial port, handshake with the Bpod firmware, and build the module
% and its parameter table.
%
% Follows the same "configure, then scan" shape as hw.Teensy.setup_interface:
% the port comes from the caller (or from a '6'-handshake probe), everything
% else is fixed by the firmware.
%
% Unlike the Teensy, the Bpod firmware has no descriptor command -- the 0.5/0.6
% board exposes a fixed hardware complement (8 ports, 8 valves, 8 PWM lines,
% 2 BNC, 4 wire), so the parameter table is authored in populateModule_ rather
% than discovered.
%
% Parameters:
%   obj - hw.Bpod instance to connect.
%
% See also: documentation/hw/hw_Bpod.md, hw.Bpod.findBoardPort,
%           hw.Bpod.populateModule_, hw.Teensy.setup_interface

% --- Resolve the port ----------------------------------------------------
port = obj.Port;
if obj.AutoDetect || isempty(port)
    vprintf(1, 'Bpod: scanning serial ports for a Bpod state machine');
    port = hw.Bpod.findBoardPort(Timeout = obj.Timeout);
    if isempty(port)
        error('hw:Bpod:NoDevice', ...
            ['No Bpod state machine answered the handshake on any available serial port. ' ...
             'Check the USB cable, that the board is flashed with Bpod_MainModule_0_6, ' ...
             'and that no serial terminal or a stale MATLAB session is holding the port.']);
    end
end
obj.Port = char(port);

% --- Open ----------------------------------------------------------------
obj.openPort_();

% The Arduino Due re-enumerates its native USB when the port opens; bytes sent
% before it finishes are silently dropped, which would show up as a handshake
% timeout on a board that is perfectly healthy.
pause(obj.BootDelay);
obj.flushInput_();

% Nothing carried over from a previous connection can be trusted: the device
% may have been left mid-trial by an aborted session, so the pump starts clean.
obj.rxBuf_ = uint8([]);
obj.matrixRunning_ = false;
obj.awaitingEpilogue_ = false;
obj.pendingEventCount_ = 0;
obj.epiHdr_ = [];

% linkReady_ gates write_/readExactly_, so it has to be true before the
% handshake can issue its first byte. A failed handshake clears it below.
obj.linkReady_ = true;

% --- Handshake -----------------------------------------------------------
% Firmware case '6' writes byte 53, then blocks 100 ms inside its own handler.
reply = uint8([]);
try
    obj.write_(uint8('6'));
    reply = obj.readExactly_(1, obj.Timeout);
catch ME
    % Demoted to a debug message: the thrown error below carries the diagnosis,
    % and the transport detail is only useful when tracing a flaky cable.
    vprintf(2, 'Bpod: transport error during handshake on %s: %s', obj.Port, ME.message);
end

if numel(reply) ~= 1 || reply(1) ~= 53
    obj.linkReady_ = false;
    obj.closePort_();
    error('hw:Bpod:BadHandshake', ...
        ['The device on %s did not answer the Bpod handshake with byte 53. ' ...
         'Verify the port and re-flash Firmware/Bpod_MainModule_0_6 if needed.'], obj.Port);
end

% Wait out the firmware's in-handler delayMicroseconds(100000) before sending
% anything else; a command issued during it lands in the USB buffer unread and
% the following reply arrives one transaction late.
pause(0.2);

% --- Firmware build ------------------------------------------------------
try
    obj.write_(uint8('F'));
    build = obj.readExactly_(1, obj.Timeout);
    if isempty(build)
        vprintf(0, 1, ['Bpod: the board on %s did not answer the firmware build query. ' ...
            'Continuing with build 0.'], obj.Port);
        obj.FirmwareBuild = 0;
    else
        obj.FirmwareBuild = double(build(1));
    end
catch ME
    % Not fatal: the handshake already proved the link, and the build number is
    % metadata. Losing it must not cost the user a rig.
    vprintf(0, 1, ME);
    obj.FirmwareBuild = 0;
end

vprintf(1, 'Bpod: connected on %s (firmware build %d, box %d)', ...
    obj.Port, obj.FirmwareBuild, obj.BoxID);

% --- Module --------------------------------------------------------------
% Reuse the existing module when there is one. Protocol.createInterfaceFromStruct_
% installs the authored modules via setModules BEFORE connecting, and
% ProtocolDesigner does the same on Modify; overwriting obj.Module here would
% throw away those hw.Parameter handles and their trial levels without erroring,
% so the session would silently run regenerated defaults.
if isempty(obj.Module)
    module = hw.Module(obj, 'Bpod', 'Bpod', uint8(1));
    obj.Module = module;
else
    module = obj.Module(1);
end

% Fs is the firmware's Timer3 tick (100 us), which is the resolution of every
% on-device event timestamp.
module.Fs = hw.Bpod.TICK_HZ;
module.Info.Port = obj.Port;
module.Info.FirmwareBuild = obj.FirmwareBuild;
module.Info.BoxID = obj.BoxID;
module.Info.StateMatrixFcn = obj.StateMatrixFcn;

% --- Parameters ----------------------------------------------------------
% populateModule_ merges into whatever is already on the module, so authored
% parameters keep their identity (and their trial levels) across a reconnect.
obj.populateModule_(module);
obj.ensureUniqueParameterNames();

% --- Initial state -------------------------------------------------------
% Drive every output low so the shadow provably matches the hardware. The
% firmware powers up with outputs clear, but a board left energized by a
% previous session's crash would otherwise stay that way -- and the shadow
% would claim it was low.
obj.resetShadow_();
obj.writeOutputs_(Force = true);

obj.modeCache_ = hw.DeviceState.Idle;

end
