classdef NanoMotorControl < handle
%NANOMOTORCONTROL Serial interface for the Arduino Nano DM320T stepper controller sketch.
%
%   NanoMotorControl wraps the sketch's newline-terminated ASCII serial
%   protocol (115200 baud). It manages the serial connection and provides
%   synchronous command/response transactions plus convenience wrappers for
%   all core protocol commands.
%
%   IMPORTANT UNITS / CONVENTIONS (per sketch)
%     - Continuous motion commands (DIR/SPD/RPM) operate in *motor* direction
%       and motor microsteps/s or motor RPM.
%     - Relative motion (MOVEDEG) is expressed in *output-shaft degrees*.
%       The firmware converts output degrees -> motor microsteps using the
%       configured gear ratio (GEAR) and OUTDIR sign.
%     - POSD? returns the commanded/open-loop *output-shaft degrees*.
%
%   Construction
%     m = NanoMotorControl(Name,Value,...)
%
%   Typical usage
%     m = NanoMotorControl(Port="COM6", AutoDetect=true);
%     m.connect();
%     m.setRPM(60);           % motor RPM (continuous)
%     p = m.positionDeg();    % output-shaft degrees (open-loop)
%     m.moveDeg(90, 120);     % +90 output degrees at 120 motor RPM
%     m.stop();
%     m.disconnect();
%
%   Public parameters (properties)
%     Port
%       Serial port name, e.g. "COM6" (Windows) or "/dev/ttyACM0" (Linux).
%       If empty, connect() will use AutoDetect (if enabled) to scan ports.
%
%     BaudRate
%       Serial baud rate used when opening the port (default 115200). To
%       change after connecting, disconnect and reconnect.
%
%     Timeout
%       Transaction timeout in seconds (default 2). Used when opening the
%       port and as the default timeout for send()/readLine().
%
%     Terminator
%       Terminator passed to configureTerminator (default "LF"). The sketch
%       accepts CR or LF; MATLAB uses this terminator for writeline/readline.
%
%     BootDelay
%       Pause (s) after opening the port (default 2) to allow Arduino reset/
%       boot before reading greeting lines or sending commands.
%
%     AutoDetect
%       If true, connect() will scan available serial ports for a device
%       whose greeting includes GreetingPattern (used when Port is empty).
%
%     ReadGreeting
%       If true (default), connect() will read and store boot/greeting lines
%       into LastGreeting.
%
%     GreetingPattern
%       Substring used by findControllerPort() to identify the controller
%       during AutoDetect (default "DM320T stepper controller ready").
%
%     StepsPerRev
%       Motor microsteps per motor revolution (FULL_STEPS_PER_REV*MICROSTEPS).
%       Used for local conversions between steps/s and motor RPM, and for
%       local step<->degree conversions that include gearing (see below).
%       Default 200*64.
%
%     GearDriverTeeth, GearDrivenTeeth, OutputDirSign
%       Local copy of the firmware's gear configuration.
%         outputRevPerMotorRev = GearDriverTeeth / GearDrivenTeeth
%         OutputDirSign = +1 or -1 (motor CW -> output CW or CCW)
%       These are used by stepsToDeg()/degToSteps() to match firmware
%       conversions. If SyncGearOnConnect=true, these properties are updated
%       from the device on connect().
%
%     SyncGearOnConnect
%       If true (default), connect() queries the device (GEAR? or STATUS?)
%       to populate Gear* and OutputDirSign.
%
%     HelpQuietTime
%       When reading multi-line text (HELP or greeting), stop after this many
%       seconds without receiving additional bytes (default 0.25).
%
%     PollPause
%       Sleep interval (s) used while polling NumBytesAvailable when reading
%       multi-line text (default 0.01).
%
%     Verbosity
%       Logging/printing level:
%         "SILENT"   : print nothing (default)
%         "INFO"     : print high-level, lay-language messages for
%                      state-changing actions (connect, enable, move, etc.)
%         "DETAILED" : print a full serial transcript (all commands sent and
%                      all lines read from the controller)
%
%     IsConnected
%       True when a serialport object exists and is valid.
%
%     OutputRevPerMotorRev
%       Dependent property: GearDriverTeeth / GearDrivenTeeth.
%
%     LastCommand
%       Most recent command string sent via send().
%
%     LastReply
%       Most recent single-line reply string read via send().
%
%     LastError
%       Most recent reply string beginning with "ERR".
%
%     LastGreeting
%       Lines read during connect() when ReadGreeting=true.
%
%   Notes
%     - send() assumes the sketch returns a single line per command.
%     - help() and the boot greeting can be multi-line; those are collected
%       using readAvailableLines().
%
%   See also serialport, serialportlist, writeline, readline, configureTerminator

    properties
        Port (1,1) string = ""
        BaudRate (1,1) double {mustBePositive} = 115200
        Timeout (1,1) double {mustBePositive} = 2
        Terminator (1,1) string = "LF"
        BootDelay (1,1) double {mustBeNonnegative} = 2

        AutoDetect (1,1) logical = false
        ReadGreeting (1,1) logical = true
        GreetingPattern (1,1) string = "DM320T stepper controller ready"

        StepsPerRev (1,1) double {mustBePositive} = 200*64

        GearDriverTeeth (1,1) double {mustBePositive, mustBeFinite} = 1
        GearDrivenTeeth (1,1) double {mustBePositive, mustBeFinite} = 1
        OutputDirSign (1,1) double {mustBeMember(OutputDirSign,[-1 1])} = 1
        SyncGearOnConnect (1,1) logical = true

        HelpQuietTime (1,1) double {mustBeNonnegative} = 0.25
        PollPause (1,1) double {mustBeNonnegative} = 0.01

        RaiseOnErr (1,1) logical = true

        Verbosity (1,1) string = "SILENT"
    end

    properties (SetAccess=private)
        LastCommand (1,1) string = ""
        LastReply (1,1) string = ""
        LastError (1,1) string = ""
        LastGreeting (:,1) string = strings(0,1)
    end

    properties (Dependent, SetAccess=private)
        IsConnected
        OutputRevPerMotorRev
    end

    properties (Access=private)
        Serial_ = []
    end

    methods
        ...existing code...
    end
end
