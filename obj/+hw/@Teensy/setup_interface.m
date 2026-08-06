function setup_interface(obj)
% setup_interface(obj)
% Open the serial port, handshake with the firmware, and build the module and
% its parameter table from the board's own descriptor.
%
% Follows the "configure, then scan" discovery model of hw.TDT_RPcox: the port
% comes from the caller, the parameter list comes from the device.
%
% Parameters:
%   obj - hw.Teensy instance to connect.
%
% See also: documentation/hw/hw_Interface_Tutorial.md, hw.Teensy.readHardwareParameters

% --- Resolve the port ----------------------------------------------------
port = obj.Port;
if obj.AutoDetect || isempty(port)
    vprintf(1, 'Teensy: scanning serial ports for an EPsychTeensy board');
    port = hw.Teensy.findBoardPort( ...
        BaudRate     = obj.BaudRate, ...
        Timeout      = obj.Timeout, ...
        BootDelay    = obj.BootDelay, ...
        DeviceSerial = obj.DeviceSerial);
    if isempty(port)
        error('hw:Teensy:NoDevice', ...
            ['No EPsychTeensy board was found on any available serial port. ' ...
             'Check the USB cable, that the board is flashed with the firmware ' ...
             'in firmware/EPsychTeensy, and that no serial terminal is holding the port.']);
    end
end
obj.Port = char(port);

% --- Open ----------------------------------------------------------------
obj.openPort_();

% A native-USB Teensy re-enumerates when the port opens; commands sent before
% it finishes are silently lost.
pause(obj.BootDelay);
obj.flushInput_();

% linkReady_ gates every transaction, so it has to be true before the
% handshake can issue its first command. A failed handshake clears it below.
obj.linkReady_ = true;

% --- Handshake -----------------------------------------------------------
reply = obj.transact_('ID?');
if ~startsWith(reply, 'ID EPsychTeensy')
    obj.linkReady_ = false;
    obj.closePort_();
    error('hw:Teensy:BadHandshake', ...
        ['The device on %s did not identify as an EPsychTeensy board (replied "%s"). ' ...
         'Verify the port and re-flash firmware/EPsychTeensy if needed.'], obj.Port, reply);
end

info = local_parseKeyValues(reply);
if isfield(info, 'FW'),    obj.FirmwareVersion = info.FW; end
if isfield(info, 'BOARD'), obj.BoardType = info.BOARD; end
if isfield(info, 'SN'),    obj.DeviceSerial = info.SN; end
if isfield(info, 'PROTO'), obj.ProtocolVersion = str2double(info.PROTO); end
if isfield(info, 'BOXES')
    obj.BoxIDs = str2double(strsplit(info.BOXES, ','));
end

if obj.ProtocolVersion ~= obj.PROTOCOL_VERSION
    % Not fatal: a mismatched grammar usually still answers ID? and DESC?, and
    % failing here would block a rig whose board is one revision behind.
    vprintf(0, 1, ['Teensy: board on %s speaks wire protocol %g but hw.Teensy speaks %g. ' ...
        'Commands may be rejected; re-flash firmware/EPsychTeensy to match.'], ...
        obj.Port, obj.ProtocolVersion, obj.PROTOCOL_VERSION);
end

vprintf(1, 'Teensy: connected to %s on %s (firmware %s, protocol %g)', ...
    obj.BoardType, obj.Port, obj.FirmwareVersion, obj.ProtocolVersion);

% --- Module --------------------------------------------------------------
% One module holds every parameter. Per-box scoping lives in the parameter
% names (x_NewTrial_1, x_NewTrial_2, ...), matching how an RPvds circuit
% exposes a flat tag table for several boxes.
if isempty(obj.Module)
    module = hw.Module(obj, 'Teensy', 'Teensy', uint8(1));
    obj.Module = module;
else
    module = obj.Module(1);
end

% Fs describes the firmware's scheduler rate, which is the resolution of every
% on-device timestamp and pulse edge.
if isfield(info, 'TICKHZ')
    tickHz = str2double(info.TICKHZ);
    if isfinite(tickHz) && tickHz > 0
        module.Fs = tickHz;
    end
end
module.Info.Port = obj.Port;
module.Info.BoardType = obj.BoardType;
module.Info.FirmwareVersion = obj.FirmwareVersion;
module.Info.DeviceSerial = obj.DeviceSerial;

% --- Parameters ----------------------------------------------------------
descriptor = obj.transactBlock_('DESC?', 'DESC');
if isempty(descriptor)
    vprintf(0, 1, ['Teensy: the board returned an empty parameter descriptor. ' ...
        'The interface is connected but has no parameters to read or write.']);
else
    obj.populateModuleParametersFromDescriptor(module, descriptor);
end
obj.ensureUniqueParameterNames();

% --- Initial state -------------------------------------------------------
obj.modeCache_ = obj.queryMode_();
obj.syncClock();
module.Info.ClockOffset = obj.ClockOffset;
module.Info.ClockUncertainty = obj.ClockUncertainty;

end


function S = local_parseKeyValues(line)
% S = local_parseKeyValues(line)
% Collect the KEY=VALUE tokens of a reply into a struct, ignoring bare words.
S = struct();
tok = strsplit(strtrim(line));
for i = 1:numel(tok)
    kv = strsplit(tok{i}, '=');
    if numel(kv) == 2 && ~isempty(kv{1})
        S.(matlab.lang.makeValidName(kv{1})) = kv{2};
    end
end
end
