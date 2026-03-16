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
        function obj = NanoMotorControl(opts)
            arguments
                opts.Port (1,1) string = ""
                opts.BaudRate (1,1) double {mustBePositive} = 115200
                opts.Timeout (1,1) double {mustBePositive} = 2
                opts.Terminator (1,1) string = "LF"
                opts.BootDelay (1,1) double {mustBeNonnegative} = 2
                opts.AutoDetect (1,1) logical = false
                opts.ReadGreeting (1,1) logical = true
                opts.GreetingPattern (1,1) string = "DM320T stepper controller ready"
                opts.StepsPerRev (1,1) double {mustBePositive} = 200*64
                opts.GearDriverTeeth (1,1) double {mustBePositive, mustBeFinite} = 1
                opts.GearDrivenTeeth (1,1) double {mustBePositive, mustBeFinite} = 1
                opts.OutputDirSign (1,1) double {mustBeMember(opts.OutputDirSign,[-1 1])} = 1
                opts.SyncGearOnConnect (1,1) logical = true
                opts.HelpQuietTime (1,1) double {mustBeNonnegative} = 0.25
                opts.PollPause (1,1) double {mustBeNonnegative} = 0.01
                opts.RaiseOnErr (1,1) logical = true
                opts.Verbosity (1,1) string = "SILENT"
            end

            obj.Port = opts.Port;
            obj.BaudRate = opts.BaudRate;
            obj.Timeout = opts.Timeout;
            obj.Terminator = opts.Terminator;
            obj.BootDelay = opts.BootDelay;
            obj.AutoDetect = opts.AutoDetect;
            obj.ReadGreeting = opts.ReadGreeting;
            obj.GreetingPattern = opts.GreetingPattern;
            obj.StepsPerRev = opts.StepsPerRev;
            obj.GearDriverTeeth = opts.GearDriverTeeth;
            obj.GearDrivenTeeth = opts.GearDrivenTeeth;
            obj.OutputDirSign = opts.OutputDirSign;
            obj.SyncGearOnConnect = opts.SyncGearOnConnect;
            obj.HelpQuietTime = opts.HelpQuietTime;
            obj.PollPause = opts.PollPause;
            obj.RaiseOnErr = opts.RaiseOnErr;

            obj.Verbosity = upper(strtrim(string(opts.Verbosity)));
            mustBeMember(obj.Verbosity, ["SILENT","INFO","DETAILED"]);
        end

        function delete(obj)
            obj.disconnect();
        end

        function tf = get.IsConnected(obj)
            tf = ~isempty(obj.Serial_) && isvalid(obj.Serial_);
        end

        function r = get.OutputRevPerMotorRev(obj)
            r = obj.GearDriverTeeth / obj.GearDrivenTeeth;
        end

        function greet = connect(obj, opts)
            arguments
                obj
                opts.Port (1,1) string = obj.Port
                opts.AutoDetect (1,1) logical = obj.AutoDetect
                opts.ReadGreeting (1,1) logical = obj.ReadGreeting
                opts.SyncGear (1,1) logical = obj.SyncGearOnConnect
            end

            if obj.IsConnected
                greet = obj.LastGreeting;
                return;
            end

            obj.logInfo("Connecting...");

            portNow = opts.Port;
            if opts.AutoDetect || portNow == ""
                portNow = obj.findControllerPort();
                if portNow == ""
                    error("NanoMotorControl:NoDevice", "No matching controller found on available serial ports.");
                end
            end

            obj.Port = portNow;

            obj.logInfo("Connecting to controller on " + obj.Port + "...");

            obj.Serial_ = serialport(obj.Port, obj.BaudRate, Timeout=obj.Timeout);
            configureTerminator(obj.Serial_, obj.Terminator);
            flush(obj.Serial_, "input");

            pause(obj.BootDelay);

            if opts.ReadGreeting
                greet = obj.readAvailableLines(QuietTime=obj.HelpQuietTime, TotalTimeout=obj.Timeout);
                obj.LastGreeting = greet;

                if obj.isDetailed() && ~isempty(greet)
                    for k = 1:numel(greet)
                        obj.logRx(greet(k));
                    end
                end
            else
                greet = strings(0,1);
            end

            obj.LastCommand = "";
            obj.LastReply = "";
            obj.LastError = "";

            if opts.SyncGear
                try
                    obj.syncGear();
                catch
                    % leave existing Gear* defaults
                end
            end

            obj.logInfo("Connected.");
        end

        function disconnect(obj)
            obj.logInfo("Disconnecting...");

            if obj.IsConnected
                try
                    flush(obj.Serial_, "input");
                catch
                end
                try
                    delete(obj.Serial_);
                catch
                end
            end
            obj.Serial_ = [];
            obj.logInfo("Disconnected.");
        end

        function ports = listPorts(obj) %#ok<MANU>
            ports = serialportlist("available");
        end

        function port = findControllerPort(obj)
            ports = serialportlist("available");
            port = "";
            if isempty(ports)
                return;
            end

            for i = 1:numel(ports)
                p = string(ports(i));
                sp = [];
                try
                    sp = serialport(p, obj.BaudRate, Timeout=obj.Timeout);
                    configureTerminator(sp, obj.Terminator);
                    flush(sp, "input");
                    pause(obj.BootDelay);

                    lines = obj.readAvailableLines(SerialObj=sp, QuietTime=obj.HelpQuietTime, TotalTimeout=obj.Timeout);
                    if any(contains(lines, obj.GreetingPattern, IgnoreCase=true))
                        port = p;
                        break;
                    end
                catch
                end

                try
                    if ~isempty(sp) && isvalid(sp)
                        delete(sp);
                    end
                catch
                end
            end
        end

        function reply = send(obj, cmd, opts)
            arguments
                obj
                cmd (1,1) string
                opts.ExpectOk (1,1) logical = false
                opts.Timeout (1,1) double {mustBePositive} = obj.Timeout
                opts.FlushBefore (1,1) logical = true
            end

            obj.assertConnected();
            if opts.FlushBefore
                flush(obj.Serial_, "input");
            end

            oldTimeout = obj.Serial_.Timeout;
            obj.Serial_.Timeout = opts.Timeout;
            try
                obj.logTx(cmd);
                writeline(obj.Serial_, cmd);
                reply = obj.readLine(Timeout=opts.Timeout);
                obj.logRx(reply);
            catch ME
                obj.Serial_.Timeout = oldTimeout;
                rethrow(ME);
            end
            obj.Serial_.Timeout = oldTimeout;

            obj.LastCommand = cmd;
            obj.LastReply = reply;

            if startsWith(reply, "ERR", IgnoreCase=false)
                obj.LastError = reply;
                if obj.isInfo()
                    obj.logInfo("Controller error: " + reply);
                end
                if obj.RaiseOnErr
                    error("NanoMotorControl:DeviceError", "%s", reply);
                end
            end

            if opts.ExpectOk && ~startsWith(reply, "OK", IgnoreCase=false)
                error("NanoMotorControl:UnexpectedReply", "Expected OK; got: %s", reply);
            end
        end

        function lines = help(obj)
            obj.assertConnected();
            obj.logTx("HELP");
            writeline(obj.Serial_, "HELP");
            lines = obj.readAvailableLines(QuietTime=obj.HelpQuietTime, TotalTimeout=obj.Timeout);

            if obj.isDetailed() && ~isempty(lines)
                for k = 1:numel(lines)
                    obj.logRx(lines(k));
                end
            end
        end

        function reply = enable(obj, tf)
            arguments
                obj
                tf (1,1) logical
            end

            if obj.isInfo()
                if tf
                    obj.logInfo("Enabling driver.");
                else
                    obj.logInfo("Disabling driver.");
                end
            end

            reply = obj.send("EN " + string(double(tf)), ExpectOk=true);
        end

        function state = enableQuery(obj)
            reply = obj.send("EN?", ExpectOk=false);
            state = logical(obj.parsePrefixedNumber(reply, "EN"));
        end

        function reply = mode(obj, modeName)
            arguments
                obj
                modeName (1,1) string
            end
            modeName = upper(strtrim(modeName));
            mustBeMember(modeName, ["USB","JOY","AUTO"]);

            if obj.isInfo()
                obj.logInfo("Setting mode to " + modeName + ".");
            end

            reply = obj.send("MODE " + modeName, ExpectOk=true);
        end

        function modeName = modeQuery(obj)
            reply = obj.send("MODE?", ExpectOk=false);
            modeName = strtrim(erase(reply, "MODE"));
        end

        function reply = dir(obj, dirName)
            arguments
                obj
                dirName (1,1) string
            end
            dirName = upper(strtrim(dirName));
            mustBeMember(dirName, ["CW","CCW"]);

            if obj.isInfo()
                obj.logInfo("Setting direction to " + dirName + ".");
            end

            reply = obj.send("DIR " + dirName, ExpectOk=true);
        end

        function dirName = dirQuery(obj)
            reply = obj.send("DIR?", ExpectOk=false);
            dirName = strtrim(erase(reply, "DIR"));
        end

        function reply = setSpeedSteps(obj, sps)
            arguments
                obj
                sps (1,1) double {mustBeFinite}
            end

            % Firmware note: SPD only flips direction when the argument is
            % negative; it does not explicitly set CW for positive values.
            % To guarantee direction, set DIR explicitly.
            if sps > 0
                dirName = "CW";
                spsMag = sps;
            elseif sps < 0
                dirName = "CCW";
                spsMag = -sps;
            else
                dirName = "";
                spsMag = 0;
            end

            if obj.isInfo()
                if dirName == ""
                    obj.logInfo(sprintf("Setting speed to %.6g steps/s.", spsMag));
                else
                    obj.logInfo(sprintf("Setting speed to %.6g steps/s (%s).", spsMag, dirName));
                end
            end

            if dirName ~= ""
                obj.send("DIR " + dirName, ExpectOk=true);
            end
            reply = obj.send(sprintf("SPD %.6g", spsMag), ExpectOk=true);
        end

        function sps = speedStepsQuery(obj)
            reply = obj.send("SPD?", ExpectOk=false);
            sps = obj.parsePrefixedNumber(reply, "SPD");
        end

        function reply = setRPM(obj, rpm)
            arguments
                obj
                rpm (1,1) double {mustBeFinite}
            end

            % Firmware note: RPM only flips direction when the argument is
            % negative; it does not explicitly set CW for positive values.
            % To guarantee direction, set DIR explicitly.
            if rpm > 0
                dirName = "CW";
                rpmMag = rpm;
            elseif rpm < 0
                dirName = "CCW";
                rpmMag = -rpm;
            else
                dirName = "";
                rpmMag = 0;
            end

            if obj.isInfo()
                if dirName == ""
                    obj.logInfo(sprintf("Setting speed to %.6g RPM.", rpmMag));
                else
                    obj.logInfo(sprintf("Setting speed to %.6g RPM (%s).", rpmMag, dirName));
                end
            end

            if dirName ~= ""
                obj.send("DIR " + dirName, ExpectOk=true);
            end
            reply = obj.send(sprintf("RPM %.6g", rpmMag), ExpectOk=true);
        end

        function rpm = rpmQuery(obj)
            reply = obj.send("RPM?", ExpectOk=false);
            rpm = obj.parsePrefixedNumber(reply, "RPM");
        end

        function reply = setLimitRPM(obj, rpm)
            arguments
                obj
                rpm (1,1) double {mustBeFinite}
            end

            if obj.isInfo()
                obj.logInfo(sprintf("Setting RPM limit to %.6g.", rpm));
            end

            reply = obj.send(sprintf("LIMRPM %.6g", rpm), ExpectOk=true);
        end

        function rpm = limitRPMQuery(obj)
            reply = obj.send("LIMRPM?", ExpectOk=false);
            rpm = obj.parsePrefixedNumber(reply, "LIMRPM");
        end

        function reply = stop(obj)
            if obj.isInfo()
                obj.logInfo("Stopping motion.");
            end
            reply = obj.send("STOP", ExpectOk=true);
        end

        function reply = cancel(obj)
            if obj.isInfo()
                obj.logInfo("Cancelling MOVE.");
            end
            reply = obj.send("CANCEL", ExpectOk=true);
        end

        function reply = zero(obj)
            if obj.isInfo()
                obj.logInfo("Zeroing position counter.");
            end
            reply = obj.send("ZERO", ExpectOk=true);
        end

        function steps = positionSteps(obj)
            reply = obj.send("POS?", ExpectOk=false);
            steps = obj.parsePrefixedNumber(reply, "POS");
        end

        function deg = positionDeg(obj)
            % Output-shaft degrees (after gearing), open-loop.
            reply = obj.send("POSD?", ExpectOk=false);
            deg = obj.parsePrefixedNumber(reply, "POSD");
        end

        function S = status(obj)
            reply = obj.send("STATUS?", ExpectOk=false);
            S = obj.parseKeyValLine(reply, "STATUS");

            % Opportunistically sync gear fields if present
            if isfield(S, "GEAR") || isfield(S, "OUTDIR")
                try
                    obj.syncGearFromStatus(S);
                catch
                end
            end
        end

        function M = moveQuery(obj)
            reply = obj.send("MOVE?", ExpectOk=false);
            M = obj.parseMoveLine(reply);
        end

        function info = moveDeg(obj, deg, rpm)
            arguments
                obj
                deg (1,1) double {mustBeFinite}
                rpm (1,1) double {mustBeFinite} = NaN
            end

            if obj.isInfo()
                if isnan(rpm)
                    obj.logInfo(sprintf("Move %.6g output-deg (speed: device default).", deg));
                else
                    obj.logInfo(sprintf("Move %.6g output-deg @ %.6g RPM.", deg, rpm));
                end
            end

            if isnan(rpm)
                cmd = sprintf("MOVEDEG %.6g", deg);
            else
                cmd = sprintf("MOVEDEG %.6g %.6g", deg, rpm);
            end

            reply = obj.send(string(cmd), ExpectOk=true);
            info = obj.parseOkMoveLine(reply);
        end

        function G = gearQuery(obj)
            %GEARQUERY Query firmware gear parameters.
            %   G = gearQuery() returns a struct with fields like DRIVER,
            %   DRIVEN, OUTDIR, OUTREV_PER_MOTORREV.
            reply = obj.send("GEAR?", ExpectOk=false);
            G = obj.parseKeyValLine(reply, "GEAR");

            if isfield(G,"DRIVER")
                obj.GearDriverTeeth = double(G.DRIVER);
            end
            if isfield(G,"DRIVEN")
                obj.GearDrivenTeeth = max(1,double(G.DRIVEN));
            end
            if isfield(G,"OUTDIR")
                od = double(G.OUTDIR);
                if od ~= 1 && od ~= -1
                    od = sign(od);
                    if od == 0, od = 1; end
                end
                obj.OutputDirSign = od;
            end
        end

        function G = setGear(obj, driverTeeth, drivenTeeth, outDirSign)
            arguments
                obj
                driverTeeth (1,1) double {mustBeFinite, mustBePositive}
                drivenTeeth (1,1) double {mustBeFinite, mustBePositive}
                outDirSign (1,1) double = NaN
            end

            if ~isnan(outDirSign)
                mustBeMember(outDirSign, [-1 1]);
            end

            drv = round(driverTeeth);
            drn = round(drivenTeeth);

            if obj.isInfo()
                if isnan(outDirSign)
                    obj.logInfo(sprintf("Setting gear ratio: driver=%d, driven=%d.", drv, drn));
                else
                    obj.logInfo(sprintf("Setting gear ratio: driver=%d, driven=%d, outdir=%d.", drv, drn, int32(outDirSign)));
                end
            end

            if isnan(outDirSign)
                cmd = sprintf("GEAR %d %d", drv, drn);
            else
                cmd = sprintf("GEAR %d %d %d", drv, drn, int32(outDirSign));
            end

            reply = obj.send(string(cmd), ExpectOk=true);
            if startsWith(reply, "OK ")
                tail = extractAfter(reply, 3);
            else
                tail = reply;
            end

            G = obj.parseKeyValLine(tail, "GEAR");

            if isfield(G,"DRIVER")
                obj.GearDriverTeeth = double(G.DRIVER);
            else
                obj.GearDriverTeeth = drv;
            end
            if isfield(G,"DRIVEN")
                obj.GearDrivenTeeth = max(1,double(G.DRIVEN));
            else
                obj.GearDrivenTeeth = drn;
            end
            if isfield(G,"OUTDIR")
                obj.OutputDirSign = double(G.OUTDIR);
            elseif ~isnan(outDirSign)
                obj.OutputDirSign = outDirSign;
            end
        end

        function syncGear(obj)
            %SYNCGEAR Update local Gear* fields from the device.
            %   Tries GEAR? first, then STATUS? as a fallback.
            try
                obj.gearQuery();
                return;
            catch
            end

            S = obj.status();
            obj.syncGearFromStatus(S);
        end

        function rpm = stepsPerSecondToRPM(obj, sps)
            arguments
                obj
                sps (1,1) double {mustBeFinite}
            end
            rpm = (sps * 60) / obj.StepsPerRev;
        end

        function sps = rpmToStepsPerSecond(obj, rpm)
            arguments
                obj
                rpm (1,1) double {mustBeFinite}
            end
            sps = (rpm * obj.StepsPerRev) / 60;
        end

        function deg = stepsToDeg(obj, steps)
            %STEPSTODEG Convert motor microsteps -> output degrees (matches firmware).
            arguments
                obj
                steps (1,1) double {mustBeFinite}
            end
            deg = (steps * 360 * obj.OutputRevPerMotorRev * obj.OutputDirSign) / obj.StepsPerRev;
        end

        function steps = degToSteps(obj, deg)
            %DEGTOSTEPS Convert output degrees -> motor microsteps (matches firmware).
            arguments
                obj
                deg (1,1) double {mustBeFinite}
            end
            denom = 360 * obj.OutputRevPerMotorRev * obj.OutputDirSign;
            if denom == 0
                error("NanoMotorControl:InvalidGear", "Invalid gear configuration (division by zero).");
            end
            steps = (deg * obj.StepsPerRev) / denom;
        end
    end

    methods (Access=private)
        function syncGearFromStatus(obj, S)
            if isfield(S,"OUTDIR")
                od = double(S.OUTDIR);
                if od ~= 1 && od ~= -1
                    od = sign(od);
                    if od == 0, od = 1; end
                end
                obj.OutputDirSign = od;
            end

            if isfield(S,"GEAR")
                g = string(S.GEAR);
                parts = split(g, "/");
                if numel(parts) == 2
                    drv = str2double(parts(1));
                    drn = str2double(parts(2));
                    if isfinite(drv) && drv > 0
                        obj.GearDriverTeeth = drv;
                    end
                    if isfinite(drn) && drn > 0
                        obj.GearDrivenTeeth = drn;
                    end
                end
            end

            obj.GearDrivenTeeth = max(1, obj.GearDrivenTeeth);
        end

        function v = verbosity_(obj)
            v = upper(strtrim(string(obj.Verbosity)));
        end

        function tf = isInfo(obj)
            tf = obj.verbosity_() == "INFO";
        end

        function tf = isDetailed(obj)
            tf = obj.verbosity_() == "DETAILED";
        end

        function logInfo(obj, msg)
            if obj.isInfo()
                fprintf("[NanoMotorControl] %s\n", string(msg));
            end
        end

        function logTx(obj, cmd)
            if obj.isDetailed()
                fprintf(">> %s\n", string(cmd));
            end
        end

        function logRx(obj, line)
            if obj.isDetailed()
                fprintf("<< %s\n", string(line));
            end
        end

        function assertConnected(obj)
            if ~obj.IsConnected
                error("NanoMotorControl:NotConnected", "Not connected. Call connect() first.");
            end
        end

        function ln = readLine(obj, opts)
            arguments
                obj
                opts.Timeout (1,1) double {mustBePositive} = obj.Timeout
            end

            obj.assertConnected();
            oldTimeout = obj.Serial_.Timeout;
            obj.Serial_.Timeout = opts.Timeout;
            try
                ln = string(readline(obj.Serial_));
            catch ME
                obj.Serial_.Timeout = oldTimeout;
                rethrow(ME);
            end
            obj.Serial_.Timeout = oldTimeout;
            ln = strtrim(ln);
        end

        function lines = readAvailableLines(obj, opts)
            arguments
                obj
                opts.SerialObj = []
                opts.MaxLines (1,1) double {mustBePositive} = 256
                opts.QuietTime (1,1) double {mustBeNonnegative} = 0.25
                opts.TotalTimeout (1,1) double {mustBeNonnegative} = 2
            end

            sp = opts.SerialObj;
            if isempty(sp)
                obj.assertConnected();
                sp = obj.Serial_;
            end

            lines = strings(0,1);
            tStart = tic;
            tLastRx = [];
            gotAny = false;

            while true
                if sp.NumBytesAvailable > 0
                    ln = strtrim(string(readline(sp)));
                    if ln ~= ""
                        lines(end+1,1) = ln; %#ok<AGROW>
                    end
                    gotAny = true;
                    tLastRx = tic;
                    if numel(lines) >= opts.MaxLines
                        break;
                    end
                else
                    if gotAny
                        if toc(tLastRx) >= opts.QuietTime
                            break;
                        end
                    else
                        if toc(tStart) >= opts.TotalTimeout
                            break;
                        end
                    end
                    pause(obj.PollPause);
                end
            end
        end

        function x = parsePrefixedNumber(obj, reply, prefix) %#ok<MANU>
            reply = strtrim(string(reply));
            prefix = strtrim(string(prefix));

            if ~startsWith(reply, prefix)
                error("NanoMotorControl:ParseError", "Expected prefix '%s'; got: %s", prefix, reply);
            end

            tail = strtrim(extractAfter(reply, strlength(prefix)));
            x = str2double(tail);
            if isnan(x)
                error("NanoMotorControl:ParseError", "Could not parse numeric value from: %s", reply);
            end
        end

        function S = parseKeyValLine(obj, reply, prefix) %#ok<MANU>
            reply = strtrim(string(reply));
            prefix = strtrim(string(prefix));

            if ~startsWith(reply, prefix)
                error("NanoMotorControl:ParseError", "Expected prefix '%s'; got: %s", prefix, reply);
            end

            toks = strsplit(reply, " ");
            S = struct();
            if numel(toks) < 2
                return;
            end

            for i = 2:numel(toks)
                kv = split(toks{i}, "=");
                if numel(kv) ~= 2
                    continue;
                end
                k = matlab.lang.makeValidName(string(kv(1)));
                vStr = string(kv(2));
                vNum = str2double(vStr);
                if ~isnan(vNum)
                    S.(k) = vNum;
                else
                    S.(k) = vStr;
                end
            end
        end

        function M = parseMoveLine(obj, reply)
            reply = strtrim(string(reply));
            if ~startsWith(reply, "MOVE")
                error("NanoMotorControl:ParseError", "Expected MOVE reply; got: %s", reply);
            end

            toks = strsplit(reply, " ");
            M = struct(Active=false);

            if numel(toks) >= 2
                flag = str2double(toks{2});
                if ~isnan(flag)
                    M.Active = logical(flag ~= 0);
                end
            end

            for i = 3:numel(toks)
                kv = split(toks{i}, "=");
                if numel(kv) ~= 2
                    continue;
                end
                k = matlab.lang.makeValidName(string(kv(1)));
                vStr = string(kv(2));
                vNum = str2double(vStr);
                if ~isnan(vNum)
                    M.(k) = vNum;
                else
                    M.(k) = vStr;
                end
            end
        end

        function info = parseOkMoveLine(obj, reply)
            reply = strtrim(string(reply));
            if ~startsWith(reply, "OK")
                error("NanoMotorControl:ParseError", "Expected OK; got: %s", reply);
            end

            info = struct();
            toks = strsplit(reply, " ");

            for i = 2:numel(toks)
                if contains(toks{i}, "=")
                    kv = split(toks{i}, "=");
                    if numel(kv) ~= 2
                        continue;
                    end
                    k = matlab.lang.makeValidName(string(kv(1)));
                    vStr = string(kv(2));
                    vNum = str2double(vStr);
                    if ~isnan(vNum)
                        info.(k) = vNum;
                    else
                        info.(k) = vStr;
                    end
                end
            end
        end
    end
end
