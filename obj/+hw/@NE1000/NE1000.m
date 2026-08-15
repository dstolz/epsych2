classdef NE1000 < hw.Interface

    % obj = hw.NE1000(port, Name=Value)
    % Hardware interface for a New Era NE-1000 Multi-Phaser programmable
    % syringe pump (SyringePump.com), controlled over RS-232.
    %
    % Speaks the pump's Basic-mode ASCII protocol (user manual #1200-01,
    % firmware V3.923, sec. 10). Commands are CR-terminated lines optionally
    % prefixed with a 0-99 network address; every reply is a packet
    % <STX><addr><status>[data]<ETX> whose status character reports the pump's
    % operational state with every exchange.
    %
    % Protocol notes (these shape the implementation):
    %   - The pump is a strict master-slave device in Basic mode: it never
    %     transmits except in answer to a command, and it will not accept a new
    %     command until it has begun answering the previous one. All I/O here
    %     is therefore synchronous single transactions, and a transaction
    %     re-entered from a timer callback (gui.SyringePump polls at 4 Hz,
    %     and MATLAB runs timers while a serialport read blocks) is DROPPED
    %     rather than allowed to interleave and desync the link.
    %   - A read whose reply goes missing serves the last value the pump
    %     reported, never []: the trial-end sweep writes whatever comes back
    %     straight into DATA. Queries are resent once; commands never are.
    %   - A pump left in Safe mode (CRC-framed packets) ignores bare ASCII
    %     commands, so connect() first sends the documented Safe-mode escape
    %     packet (manual sec. 10.2.2) to force Basic mode. In Basic mode the
    %     pump accepts either framing, so the escape is harmless when already
    %     in Basic mode.
    %   - Alarms (stall, reset, program error) must be acknowledged before the
    %     pump accepts changes; per the manual, an alarm status carried in the
    %     reply to any valid command IS the acknowledgment. transact_ logs the
    %     alarm and records it in LastAlarm.
    %   - Numeric command data is "maximum of 4 digits plus 1 decimal point"
    %     (sec. 10.2.1); formatFloat_ renders every outgoing float to fit.
    %   - Rate units cannot be changed while the pump is pumping, so writes to
    %     Rate first try '<value><units>' and fall back to the bare value.
    %
    % The pump's Pumping Program (Phases, loops, event traps) is deliberately
    % NOT modeled: this interface drives the pump as a single-rate dispenser,
    % the way a behavioral rig meters reward. Program the pump's Phase memory
    % from PUMPTERM / the keypad if a multi-Phase program is needed, and use
    % only Start/Stop from here.
    %
    % Parameters
    %   port    - Serial port name, e.g. 'COM4'. Empty with AutoDetect=true
    %             probes available ports with a VER query.
    %
    % Name=Value options
    %   BaudRate (double)        - 300|1200|2400|9600|19200. Default 19200
    %   Address (double)         - Pump network address 0-99. Default 0
    %   SyringeDiameter (double) - Inside diameter (mm) pushed at connect.
    %                              0 keeps the pump's stored value. Default 0
    %   RateUnits (char)         - 'UM'|'MM'|'UH'|'MH' (µL/mL per min/hr)
    %                              used when writing Rate. Default 'MH'
    %   TTLTrigger (logical)     - Hand start/stop control to the pump's TTL
    %                              Operational Trigger input. Default false
    %   TriggerMode (char)       - Trigger mode written when TTLTrigger is on.
    %                              Default 'LE' (see TRIGGER_MODES)
    %   Connect (logical)        - Connect on construction. Default true
    %   AutoDetect (logical)     - Probe ports for a pump at connect. Default false
    %   Timeout (double)         - Transaction timeout in seconds. Default 1
    %
    % Properties
    %   Port, BaudRate, Address, Timeout - Connection settings.
    %   IsConnected              - True when the port is open and the pump answered VER.
    %   Module                   - Single hw.Module holding the parameter table.
    %   mode                     - Current hw.DeviceState (host-side; the pump
    %                              has no session mode. Leaving Record/Preview
    %                              stops the pump).
    %   TTLTrigger, TriggerMode  - Whether the pump's TTL Operational Trigger
    %                              input may start/stop it, and in which mode.
    %   FirmwareVersion          - e.g. 'NE1000V3.923', reported at connect.
    %   LastAlarm                - Most recent alarm character (R/S/T/E/O), '' when none.
    %   DispensedUnits           - Units of the last DIS reply, 'UL' or 'ML'.
    %
    % Methods
    %   connect, disconnect       - Connection management.
    %   get_parameter, set_parameter, trigger - hw.Interface contract.
    %   selfTest                  - Pre-flight diagnostics for epsych.SelfTest.
    %   setModules                - Replace the Module array while offline.
    %
    % Usage
    %   iface = hw.NE1000('COM4');
    %   iface = hw.NE1000('', AutoDetect=true, SyringeDiameter=21.69);
    %
    %   % Offline construction for serialization round-trip
    %   iface = hw.NE1000('COM4', Connect=false);
    %
    %   iface.set_parameter('Rate', 0.5);       % in RateUnits
    %   iface.set_parameter('Volume', 0.05);    % 0 = continuous pumping
    %   iface.trigger('Start');
    %   iface.trigger('Stop');
    %
    %   % Hand start/stop to a rig digital line wired to pin 2
    %   iface.TriggerMode = 'ST';      % falling edge starts, and only starts
    %   iface.TTLTrigger  = true;
    %
    % See also: documentation/hw/hw_NE1000.md, documentation/hw/hw_Interface.md,
    %           hw.Module, hw.Parameter, hw.Teensy, peripherals.PumpCom


    properties
        Port (1,:) char = ''              % serial port name, e.g. 'COM4'
        BaudRate (1,1) double {mustBeMember(BaudRate,[300 1200 2400 9600 19200])} = 19200
        Address (1,1) double {mustBeInteger, mustBeInRange(Address,0,99)} = 0
        Timeout (1,1) double = 1          % transaction timeout in seconds
        HW = []                           % serialport handle (also required by hw.Parameter)

        AutoDetect (1,1) logical = false  % probe ports with a VER query at connect

        % Inside diameter (mm) pushed to the pump at connect. The diameter
        % scales every rate and volume the pump computes, and it lives in the
        % pump's non-volatile memory, so 0 means "trust what the pump has".
        SyringeDiameter (1,1) double {mustBeInRange(SyringeDiameter,0,50)} = 0

        % Units attached when writing Rate: UM=µL/min, MM=mL/min, UH=µL/hr,
        % MH=mL/hr. Changing units is only possible while the pump is stopped.
        RateUnits (1,2) char {mustBeMember(RateUnits,{'UM','MM','UH','MH'})} = 'MH'

        % Whether the pump's TTL Operational Trigger input (DB-9 pin 2) may
        % start and stop it. False writes 'TRG OF'; true writes TriggerMode.
        % The configuration is asserted at connect and on every assignment,
        % so a pump left triggerable by the keypad is disabled unless the
        % host asks for it -- a floating trigger line must not dispense.
        TTLTrigger (1,1) logical = false

        % Trigger mode written when TTLTrigger is on; see TRIGGER_MODES for
        % the codes and TRIGGER_LABELS for what each does. 'LE' (level:
        % rising edge starts, falling edge stops) is the default because it
        % maps a reward gate straight onto a rig's digital output line.
        % Deliberately not exposed in any GUI: the rig's wiring decides it,
        % so it belongs to the paradigm's code, not to the operator.
        TriggerMode (1,2) char = 'LE'

        % TTL on the cached DIS (volume dispensed) read. One DIS answers both
        % VolumeInfused and VolumeWithdrawn, so the runtime's trial-end sweep
        % over the readable parameters costs one round-trip rather than two.
        DispenseCacheInterval (1,1) double = 0.05
    end

    properties (SetObservable, AbortSet)
        mode  % Current device state (hw.DeviceState)
    end

    properties (Dependent)
        % True when the port is open and the pump answered VER. Deliberately
        % undecorated: MATLAB rejects size/class validation on a property
        % inherited from an abstract declaration.
        IsConnected
    end

    properties (SetAccess = protected)
        Module                            % hw.Module array
        FirmwareVersion (1,:) char = ''   % VER reply, e.g. 'NE1000V3.923'
        LastAlarm (1,:) char = ''         % most recent alarm code (R/S/T/E/O)

        % Units the pump reported with the most recent DIS reply, 'UL' or
        % 'ML', '' before the first read. The pump picks them from the
        % syringe diameter rather than from anything the host sets, so a
        % display that labels VolumeInfused/VolumeWithdrawn must read them
        % here rather than assume RateUnits applies.
        DispensedUnits (1,:) char = ''
    end

    properties (Constant)
        Type = "NE1000"

        STX = char(2)   % start-of-packet marker in every reply
        ETX = char(3)   % end-of-packet marker in every reply

        % Prompt characters the pump reports with every reply (manual 10.2.4)
        % and their operator-facing labels, index-aligned.
        STATUS_CHARS  = 'IWSPTUX'
        STATUS_LABELS = {'Infusing','Withdrawing','Stopped','Paused', ...
                         'TimedPause','TriggerWait','Purging'}

        % TTL Operational Trigger modes (manual 6.5) and what each does,
        % index-aligned. 'OF' is deliberately absent: disabling the trigger
        % is TTLTrigger's job, so there is only one way to say it.
        TRIGGER_MODES = {'FT','FH','F2','LE','ST','T2','SP','P2','RL','RH','SL','SH'}
        TRIGGER_LABELS = {'Foot switch: falling edge starts or stops', ...
                          'Foot switch hold: falling edge starts, rising edge stops', ...
                          'Foot switch reversed: rising edge starts or stops', ...
                          'Level: rising edge starts, falling edge stops', ...
                          'Start only: falling edge starts', ...
                          'Start only reversed: rising edge starts', ...
                          'Stop only: falling edge stops', ...
                          'Stop only reversed: rising edge stops', ...
                          'Start on a low level', ...
                          'Start on a high level', ...
                          'Stop on a low level', ...
                          'Stop on a high level'}

        % Alarm codes (manual 10.2.4) and labels, index-aligned.
        ALARM_CHARS  = 'RSTEO'
        ALARM_LABELS = {'Pump was reset (power interrupted)', ...
                        'Pump motor stalled', ...
                        'Safe-mode communications timeout', ...
                        'Pumping Program error', ...
                        'Pumping Program Phase out of range'}
    end

    properties (Access = protected)
        % Connection state. Reachable by test subclasses (tmp/NE1000_Mock).
        linkReady_ (1,1) logical = false    % port open and VER handshake accepted
        modeCache_ (1,1) hw.DeviceState = hw.DeviceState.Idle

        % Cached DIS reply: struct('inf',double,'wdr',double,'units',char).
        dispCache_ = []
        dispCacheTic_ = []

        % True while a command is on the wire. The pump answers exactly one
        % command at a time, and MATLAB dispatches timer callbacks while a
        % serialport read blocks, so without this guard gui.SyringePump's
        % 4 Hz poll lands inside another transaction and the two consume
        % each other's replies (see transact_).
        busy_ (1,1) logical = false

        % True while the trigger configuration the pump reported is being
        % copied into TTLTrigger/TriggerMode, so the setters do not turn a
        % read straight back into a write.
        applyingTrigger_ (1,1) logical = false

        % Last value each wire query actually returned, keyed by wire name.
        % Serves a read whose reply went missing, so a dropped packet
        % degrades to a stale value instead of to [] (see readOne_).
        lastGood_ = struct()
    end


    methods

        function obj = NE1000(port, options)
            % obj = hw.NE1000(port, Name=Value)
            % Construct an NE-1000 interface and optionally connect.
            %
            % Parameters
            %   port - Serial port name. Default '' (requires AutoDetect).
            % Name=Value
            %   BaudRate (double)        - Serial baud rate. Default 19200
            %   Address (double)         - Pump network address 0-99. Default 0
            %   SyringeDiameter (double) - Diameter (mm) pushed at connect; 0 keeps
            %                              the pump's stored value. Default 0
            %   RateUnits (char)         - Units for Rate writes. Default 'MH'
            %   TTLTrigger (logical)     - Let the pump's TTL trigger input start
            %                              and stop it. Default false
            %   TriggerMode (char)       - Mode used when TTLTrigger is on.
            %                              Default 'LE'
            %   Connect (logical)        - Connect on construction. Default true
            %   AutoDetect (logical)     - Probe ports for a pump. Default false
            %   Timeout (double)         - Transaction timeout (s). Default 1
            arguments
                port (1,:) char = ''
                options.BaudRate (1,1) double = 19200
                options.Address (1,1) double = 0
                options.SyringeDiameter (1,1) double = 0
                options.RateUnits (1,2) char = 'MH'
                options.TTLTrigger (1,1) logical = false
                options.TriggerMode (1,2) char = 'LE'
                options.Connect (1,1) logical = true
                options.AutoDetect (1,1) logical = false
                options.Timeout (1,1) double = 1
            end

            obj.Port = port;
            obj.BaudRate = options.BaudRate;
            obj.Address = options.Address;
            obj.SyringeDiameter = options.SyringeDiameter;
            obj.RateUnits = options.RateUnits;
            obj.TriggerMode = options.TriggerMode;
            obj.TTLTrigger = options.TTLTrigger;
            obj.AutoDetect = options.AutoDetect;
            obj.Timeout = options.Timeout;
            obj.Module = hw.Module.empty(1, 0);

            if options.Connect
                obj.connect();
            end
        end

        function delete(obj)
            % delete(obj)
            % Stop the pump and release the serial port.
            %
            % The stop matters: a pump left infusing when MATLAB errors out
            % keeps pushing the syringe until it stalls on the collar clamp.
            obj.close_interface();
        end

        function connect(obj)
            % connect(obj)
            % Open the serial port, handshake with VER, and build the
            % parameter table. Safe to call when already connected.
            if obj.IsConnected
                return
            end
            obj.setup_interface();
        end

        function disconnect(obj)
            % disconnect(obj)
            % Stop the pump and close the serial port. Not on the abstract
            % contract, but RunExpt.onCloseRequest and epsych.SelfTest call it.
            obj.close_interface();
        end

        function tf = get.IsConnected(obj)
            % tf = get.IsConnected(obj)
            % True when the port handle is live and the pump handshook.
            %
            % HW normally holds a serialport handle, but a test subclass that
            % overrides the transport seam may park a non-handle there, so the
            % validity check only applies when there is a handle to check.
            tf = obj.linkReady_ && ~isempty(obj.HW);
            if tf && isa(obj.HW, 'handle')
                tf = isvalid(obj.HW);
            end
        end

        function m = get.mode(obj)
            % m = get.mode(obj)
            % Current device state, served from cache.
            %
            % RunExpt.PsychTimerRunTime reads this on every 10 ms tick and
            % stops the session when any interface reports Idle, so this must
            % be cheap and must never fabricate Idle. The pump has no session
            % mode of its own; the cache changes only through set.mode.
            m = obj.modeCache_;
        end

        function set.mode(obj, m)
            % set.mode(obj, m)
            % Record the requested device state.
            %
            % The NE-1000 has no run/standby concept, but leaving Record or
            % Preview stops any pumping in progress so a session teardown can
            % never strand the motor running.
            m = hw.DeviceState(m);
            if m.isIdle() && obj.linkReady_
                obj.transact_('STP');
            end
            obj.modeCache_ = m;
        end

        function set.TTLTrigger(obj, tf)
            % set.TTLTrigger(obj, tf)
            % Hand start/stop control to the pump's TTL trigger input, or
            % take it back. A connected pump is reconfigured immediately;
            % otherwise the state is asserted at connect.
            obj.TTLTrigger = tf;
            if ~obj.applyingTrigger_
                obj.pushTrigger_();
            end
        end

        function set.TriggerMode(obj, code)
            % set.TriggerMode(obj, code)
            % Choose which TTL trigger mode is written when TTLTrigger is on.
            % Rejected rather than logged: an unknown mode is a programming
            % error, and silently keeping the old one would leave the rig
            % wired for a contingency the pump is not running.
            code = upper(strtrim(char(code)));
            if ~ismember(code, hw.NE1000.TRIGGER_MODES)
                error('hw:NE1000:BadTriggerMode', ...
                    '"%s" is not a trigger mode. Use one of: %s.', ...
                    code, strjoin(hw.NE1000.TRIGGER_MODES, ', '));
            end
            obj.TriggerMode = code;
            if ~obj.applyingTrigger_ && obj.TTLTrigger
                obj.pushTrigger_();
            end
        end

        function setModules(obj, modules)
            % setModules(obj, modules)
            % Replace the Module array. Used by Protocol.createInterfaceFromStruct_
            % when restoring a saved protocol and by ProtocolDesigner on Modify.
            arguments
                obj
                modules (1,:) hw.Module
            end
            if obj.IsConnected
                error('hw:NE1000:ModulesWhileConnected', ...
                    'Disconnect before replacing modules on a live NE1000 interface.');
            end
            obj.Module = modules;
        end

        % --- Parameter I/O -------------------------------------------------

        function value = get_parameter(obj, name, options)
            % value = get_parameter(obj, name, Name=Value)
            % Read one or more parameters, preserving the requested order.
            %
            % VolumeInfused and VolumeWithdrawn are served from a shared DIS
            % cache (see DispenseCacheInterval); everything else is one query
            % round-trip. Offline, the locally cached hw.Parameter value is
            % served so a protocol can be edited with no pump attached.
            %
            % Parameters
            %   name - Parameter name(s) or hw.Parameter handle(s).
            % Name=Value
            %   includeInvisible (logical)         - Include hidden parameters. Default true
            %   silenceParameterNotFound (logical) - Suppress the not-found warning. Default false
            %
            % Returns:
            %   value - Value, or cell array of values for multiple names.
            arguments
                obj
                name
                options.includeInvisible (1,1) logical = true
                options.silenceParameterNotFound (1,1) logical = false
            end

            if isa(name, 'hw.Parameter')
                P = name;
                name = {P.Name};
            else
                if ischar(name) || isstring(name)
                    name = cellstr(name);
                end
                P = obj.find_parameter(name, ...
                    includeInvisible = options.includeInvisible, ...
                    silenceParameterNotFound = options.silenceParameterNotFound);
            end

            if isempty(P)
                value = [];
                return
            end

            value = cell(size(P));
            for i = 1:numel(P)
                if obj.IsConnected
                    value{i} = obj.readOne_(obj.wireName_(P(i)), P(i));
                else
                    value{i} = P(i).Value;
                end
            end

            % Restore the caller's requested order.
            [~, idx] = ismember(name, {P.Name});
            idx(idx == 0) = [];
            if numel(idx) == numel(value)
                value = value(idx);
            end

            if isscalar(value)
                value = value{1};
            end
        end

        function result = set_parameter(obj, name, value)
            % result = set_parameter(obj, name, value)
            % Write one or more parameters.
            %
            % Parameters
            %   name  - Parameter name(s) or hw.Parameter handle(s).
            %   value - Scalar (expanded across all targets) or per-target values.
            %
            % Returns:
            %   result - True when every write was accepted.
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name, includeInvisible = true);
            end

            if isempty(P)
                result = false;
                return
            end

            % The pump has no waveform channel; a stimulus has no
            % representation on this wire. Named here so the skip reads as
            % intentional rather than failing per-trial as a type error.
            if hw.Interface.isStimulusValue(value)
                vprintf(2, ['hw.NE1000: "%s" holds a stimulus, which a syringe ' ...
                    'pump cannot express; value kept host-side'], P(1).Name)
                result = true;
                return
            end

            if ~iscell(value)
                value = {value};
            end
            if isscalar(value) && ~isscalar(P)
                value = repmat(value, size(P));
            end

            result = true;

            % Offline writes are a no-op: hw.Parameter.set.Value has already
            % stored the value locally, which is what ProtocolDesigner reads back.
            if ~obj.IsConnected
                return
            end

            for i = 1:numel(P)
                ok = obj.writeOne_(obj.wireName_(P(i)), value{i});
                result = result && ok;
            end

            obj.dispCacheTic_ = [];
        end

        function t = trigger(obj, name)
            % t = trigger(obj, name)
            % Pulse one or more trigger parameters: 'Start' runs the pump
            % ('RUN'), 'Stop' stops/pauses it ('STP'), 'ClearVolume' zeros both
            % dispensed-volume accumulators ('CLD INF' + 'CLD WDR').
            %
            % Returns:
            %   t - Timestamp as a `now` serial date number. hw.Parameter.Trigger
            %       assigns this straight into lastUpdated (1,1) double, so it
            %       must be a double and not a datetime.
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name, includeInvisible = true);
            end

            if isempty(P) || ~obj.IsConnected
                t = now;
                return
            end

            for i = 1:numel(P)
                switch obj.wireName_(P(i))
                    case 'Start'
                        R = obj.transact_('RUN');
                        if ~isempty(R.err)
                            vprintf(0, 1, 'NE1000: RUN was rejected: %s', R.err);
                        end
                    case 'Stop'
                        obj.transact_('STP');
                    case 'ClearVolume'
                        % Only valid while the Pumping Program is not
                        % operating; a rejection is logged by transact_.
                        obj.transact_('CLDINF');
                        obj.transact_('CLDWDR');
                    otherwise
                        vprintf(0, 1, 'NE1000: "%s" is not a trigger this pump exposes', P(i).Name);
                end
            end
            t = now;

            obj.dispCacheTic_ = [];
        end

        % --- Diagnostics ---------------------------------------------------

        function results = selfTest(obj, options)
            % results = selfTest(obj, Invasive=false)
            % Pre-flight diagnostics for epsych.SelfTest. Never throws.
            %
            % Non-invasive checks make no hardware calls. The invasive pass may
            % open the port and must restore the connection state it found.
            arguments
                obj
                options.Invasive (1,1) logical = false
            end

            results = hw.Interface.selfTestResult();

            % --- Port present ------------------------------------------------
            try
                available = cellstr(serialportlist('available'));
            catch
                available = {};
            end

            if isempty(obj.Port)
                if obj.AutoDetect
                    results(end + 1) = hw.Interface.selfTestResult('NE1000 Port', 'info', ...
                        'No port configured; AutoDetect will probe on connect.');
                else
                    results(end + 1) = hw.Interface.selfTestResult('NE1000 Port', 'fail', ...
                        'No serial port configured.', ...
                        Remedy = 'Set the Port option in ProtocolDesigner, or enable AutoDetect.');
                end
            elseif ismember(obj.Port, available) || obj.IsConnected
                results(end + 1) = hw.Interface.selfTestResult('NE1000 Port', 'pass', ...
                    sprintf('Port %s is present.', obj.Port));
            else
                results(end + 1) = hw.Interface.selfTestResult('NE1000 Port', 'fail', ...
                    sprintf('Port %s is not among the available serial ports.', obj.Port), ...
                    Detail = sprintf('Available: %s', strjoin(available, ', ')), ...
                    Remedy = 'Check the RS-232 (or USB-RS232) cable and pump power.');
            end

            if ~options.Invasive
                results(end + 1) = hw.Interface.selfTestResult('NE1000 Handshake', 'skip', ...
                    'Firmware handshake requires an invasive test.');
                return
            end

            % --- Handshake ----------------------------------------------------
            wasConnected = obj.IsConnected;
            try
                if ~wasConnected
                    obj.connect();
                end

                if ~obj.IsConnected
                    results(end + 1) = hw.Interface.selfTestResult('NE1000 Handshake', 'fail', ...
                        'Could not open a connection to the pump.', ...
                        Remedy = ['Verify the port, address, and baud rate match the ' ...
                            'pump''s Setup values (hold Diameter key on the keypad).']);
                else
                    results(end + 1) = hw.Interface.selfTestResult('NE1000 Handshake', 'pass', ...
                        sprintf('Pump answered as %s (address %d, %d baud).', ...
                            obj.FirmwareVersion, obj.Address, obj.BaudRate));
                    if ~isempty(obj.LastAlarm)
                        results(end + 1) = hw.Interface.selfTestResult('NE1000 Alarm', 'warn', ...
                            sprintf('Pump reported an alarm at connect: %s.', obj.alarmLabel_(obj.LastAlarm)), ...
                            Remedy = 'The alarm was acknowledged, but check the pump and syringe before running.');
                    end
                end

                if ~wasConnected
                    obj.disconnect();
                end
            catch ME
                results(end + 1) = hw.Interface.selfTestResult('NE1000 Handshake', 'fail', ...
                    'Handshake raised an error.', ...
                    Detail = ME.message, ...
                    Remedy = 'Close any program holding the port, check baud rate, then retry.');
                try
                    if ~wasConnected
                        obj.disconnect();
                    end
                catch
                end
            end
        end

    end  % public methods


    methods (Access = protected)

        function setup_interface(obj)
            % setup_interface(obj)
            % Open the serial port, force Basic mode, handshake with VER, push
            % the syringe diameter, and build the parameter table.

            % --- Resolve the port -------------------------------------------
            port = obj.Port;
            if obj.AutoDetect || isempty(port)
                vprintf(1, 'NE1000: probing serial ports for a pump at address %d', obj.Address);
                port = hw.NE1000.findPumpPort( ...
                    BaudRate = obj.BaudRate, ...
                    Address  = obj.Address, ...
                    Timeout  = obj.Timeout);
                if isempty(port)
                    error('hw:NE1000:NoDevice', ...
                        ['No NE-1000 pump answered on any available serial port at %d baud, ' ...
                         'address %d. Check the cable, pump power, and that the pump''s ' ...
                         'Setup address and baud rate match.'], obj.BaudRate, obj.Address);
                end
            end
            obj.Port = char(port);

            % --- Open --------------------------------------------------------
            obj.openPort_();

            % linkReady_ gates every transaction, so it must be true before the
            % handshake can issue its first command. A failed handshake clears it.
            obj.linkReady_ = true;

            % A pump stranded in Safe mode ignores bare ASCII; this exact byte
            % sequence (manual 10.2.2) returns it to Basic mode and is accepted
            % harmlessly when already in Basic mode.
            obj.writeRaw_(uint8([2 8 'SAF0' 85 67 3]));
            pause(0.1);
            obj.flushInput_();

            % --- Handshake ---------------------------------------------------
            R = obj.transact_('VER');
            if R.ok && ~isempty(R.alarm)
                % A pump fresh from power-up answers its first command with the
                % reset alarm instead of the data. That reply acknowledged the
                % alarm (manual 10.3), so the query simply repeats.
                R = obj.transact_('VER');
            end
            if ~R.ok || isempty(R.data) || ~startsWith(R.data, 'NE')
                obj.linkReady_ = false;
                obj.closePort_();
                error('hw:NE1000:BadHandshake', ...
                    ['The device on %s did not identify as a New Era pump ' ...
                     '(VER replied "%s"). Verify the port, the pump''s network ' ...
                     'address (%d), and its baud rate (%d).'], ...
                    obj.Port, R.data, obj.Address, obj.BaudRate);
            end
            obj.FirmwareVersion = R.data;
            vprintf(1, 'NE1000: connected to %s on %s (address %d, %d baud)', ...
                obj.FirmwareVersion, obj.Port, obj.Address, obj.BaudRate);

            % --- Safe initial state ------------------------------------------
            % Stop anything a previous session (or Power Failure mode) left
            % running before touching settings; most setters are rejected while
            % the Pumping Program is operating.
            obj.transact_('STP');

            if obj.SyringeDiameter > 0
                R = obj.transact_(sprintf('DIA%s', hw.NE1000.formatFloat_(obj.SyringeDiameter)));
                if ~isempty(R.err)
                    vprintf(0, 1, 'NE1000: setting syringe diameter %.4g mm was rejected: %s', ...
                        obj.SyringeDiameter, R.err);
                end
            end

            % The TTL trigger configuration is asserted on every connect, not
            % read: the pump keeps it in non-volatile memory, so a trigger
            % someone enabled from the keypad would otherwise still be able
            % to start this session's pump behind the host's back.
            obj.pushTrigger_();

            % --- Module and parameters ---------------------------------------
            if isempty(obj.Module)
                module = hw.Module(obj, 'NE1000', 'Pump', uint8(1));
                obj.Module = module;
            else
                module = obj.Module(1);
            end
            module.Info.Port = obj.Port;
            module.Info.Address = obj.Address;
            module.Info.FirmwareVersion = obj.FirmwareVersion;

            obj.populateModule_(module);
            obj.ensureUniqueParameterNames();

            obj.modeCache_ = hw.DeviceState.Standby;
        end

        function close_interface(obj)
            % close_interface(obj)
            % Stop the pump and release the serial port.
            %
            % The STP is the safety backstop: the pump keeps executing its
            % Pumping Program with no host attached, so simply dropping the
            % port would leave an infusion running.
            if obj.IsConnected
                try
                    obj.transact_('STP');
                catch ME
                    vprintf(0, 1, ME);
                end
            end
            obj.linkReady_ = false;
            obj.closePort_();
            obj.dispCache_ = [];
            obj.dispCacheTic_ = [];
        end

        function populateModule_(obj, module)
            % populateModule_(obj, module)
            % Build the fixed hw.Parameter table on `module`, merging with any
            % parameters a restored protocol already placed there. Matching is
            % on the hardware name so a rename by ensureUniqueParameterNames
            % cannot cause duplicates.
            arguments
                obj
                module (1,1) hw.Module
            end

            existingNames = arrayfun(@hw.Interface.getHardwareParameterName, ...
                module.Parameters, UniformOutput = false);

            specs = local_parameterSpecs_(obj.RateUnits);

            nAdded = 0;
            for k = 1:numel(specs)
                name = specs(k).Name;
                if ismember(name, existingNames)
                    continue
                end
                nv = namedargs2cell(specs(k).Options);
                P = module.add_parameter(name, specs(k).Value, nv{:});
                obj.setHardwareParameterName(P, name);
                nAdded = nAdded + 1;
            end

            vprintf(2, 'NE1000: module "%s" holds %d parameter(s) (%d added)', ...
                module.Name, numel(module.Parameters), nAdded);
        end

    end  % protected methods


    % ---- Transport seam.
    % Isolated so a mock (tmp/NE1000_Mock) can override exactly this surface
    % and leave every line of protocol logic running unchanged.
    methods (Access = protected)

        function openPort_(obj)
            % openPort_(obj)
            % Open the serial port with the pump's fixed 8N1 framing. Reads
            % terminate on ETX (0x03); writes terminate with CR (0x0D).
            obj.HW = serialport(obj.Port, obj.BaudRate, ...
                DataBits = 8, StopBits = 1, Parity = 'none', ...
                FlowControl = 'none', Timeout = obj.Timeout);
            configureTerminator(obj.HW, 3, 'CR');
            flush(obj.HW, 'input');
        end

        function closePort_(obj)
            % closePort_(obj)
            % Delete the serialport handle if present.
            if ~isempty(obj.HW) && isvalid(obj.HW)
                try
                    flush(obj.HW, 'input');
                catch
                end
                delete(obj.HW);
            end
            obj.HW = [];
        end

        function writeLine_(obj, s)
            % writeLine_(obj, s)
            % Write one CR-terminated command line.
            writeline(obj.HW, s);
        end

        function writeRaw_(obj, bytes)
            % writeRaw_(obj, bytes)
            % Write raw bytes with no terminator (Safe-mode escape packet).
            write(obj.HW, bytes, 'uint8');
        end

        function s = readPacket_(obj)
            % s = readPacket_(obj)
            % Read one ETX-terminated reply, trimmed of the STX marker.
            % Returns '' on timeout rather than throwing.
            %
            % MATLAB raises a warning of its own whenever readline times out.
            % A dropped reply is an expected event on this link — transact_
            % reports it through vprintf and resends queries — so its
            % four-line duplicate is suppressed for the span of this one read.
            ws = warning('off', 'all');
            try
                s = char(readline(obj.HW));
            catch
                s = '';
            end
            warning(ws);

            if isempty(s)
                return
            end
            if isempty(s)
                return
            end
            i = find(s == hw.NE1000.STX, 1, 'last');
            if ~isempty(i)
                s = s(i + 1:end);
            end
        end

        function flushInput_(obj)
            % flushInput_(obj)
            % Discard buffered input before starting a transaction.
            try
                flush(obj.HW, 'input');
            catch
            end
        end

    end  % protected transport seam


    methods (Access = private)

        % --- Transactions --------------------------------------------------

        function R = transact_(obj, cmd, options)
            % R = transact_(obj, cmd, Quiet=false)
            % Send one command and parse its single reply packet.
            %
            % Name=Value
            %   Quiet - Do not log a command error. For a command sent as a
            %           probe, where a rejection is one of the anticipated
            %           answers and the caller has somewhere else to go.
            %
            % Returns a struct with fields:
            %   ok     - True when a well-formed reply arrived.
            %   status - Prompt character (I/W/S/P/T/U/X), '' when none.
            %   alarm  - Alarm code (R/S/T/E/O), '' when none.
            %   data   - Reply payload after the status field.
            %   err    - Command error ('?', 'NA', 'OOR', 'COM', 'IGN'), '' when none.
            %
            % Following house style, failures warn through vprintf and degrade
            % rather than throwing, so a flaky RS-232 link does not abort a
            % session mid-trial.
            arguments
                obj
                cmd (1,:) char
                options.Quiet (1,1) logical = false
            end

            R = struct('ok', false, 'status', '', 'alarm', '', 'data', '', 'err', '');
            if ~obj.IsConnected
                return
            end

            % One command, one reply, no overlap. The pump will not accept a
            % new command until it has begun answering the previous one, and
            % MATLAB runs timer callbacks while a serialport read blocks — so
            % gui.SyringePump's 4 Hz poll can fire in the middle of the
            % runtime's trial-end sweep. Each would then flush and consume the
            % other's reply, and the link stays a packet out of step for the
            % rest of the session. The nested command is dropped instead; its
            % caller falls back to the last value the pump reported.
            if obj.busy_
                vprintf(3, 'NE1000: "%s" skipped; another transaction is in flight', cmd);
                return
            end

            obj.busy_ = true;
            try
                R = obj.runTransaction_(cmd, options.Quiet);
            catch ME
                vprintf(0, 1, ME);
            end
            obj.busy_ = false;
        end

        function R = runTransaction_(obj, cmd, quiet)
            % R = runTransaction_(obj, cmd, quiet)
            % Body of one transaction, with the link already claimed by
            % transact_. Same return struct.
            R = struct('ok', false, 'status', '', 'alarm', '', 'data', '', 'err', '');

            % A query only reports state, so a missing reply is worth one
            % resend. RUN, STP, CLD and every setter are NOT resent: the pump
            % may well have performed the first copy before its reply went
            % astray, and a second RUN is a second dose of reward.
            if hw.NE1000.isQuery_(cmd)
                attempts = 2;
            else
                attempts = 1;
            end

            raw = '';
            for a = 1:attempts
                try
                    obj.flushInput_();
                    obj.writeLine_(sprintf('%d%s', obj.Address, cmd));
                    raw = obj.readPacket_();
                catch ME
                    vprintf(0, 1, 'NE1000: transport error on "%s": %s', cmd, ME.message);
                    return
                end
                if ~isempty(raw)
                    break
                end
                if a < attempts
                    vprintf(2, 'NE1000: no reply to "%s"; retrying once', cmd);
                end
            end

            if isempty(raw)
                vprintf(0, 1, 'NE1000: timed out waiting for a reply to "%s"', cmd);
                return
            end

            R = hw.NE1000.parseResponse_(raw);

            if ~isempty(R.alarm)
                % Per the manual, this reply IS the acknowledgment of the alarm.
                obj.LastAlarm = R.alarm;
                vprintf(0, 1, 'NE1000: alarm - %s', obj.alarmLabel_(R.alarm));
            end

            % '?NA' to STP means the pump was already stopped, which is what
            % every STP issued here is asking for — connect, teardown, leaving
            % Record, and the operator's Stop button alike. Reporting it as an
            % error puts a red line in the log for a pump behaving correctly.
            expected = quiet || (strcmp(cmd, 'STP') && strcmp(R.err, 'NA'));
            if ~isempty(R.err) && ~expected
                vprintf(0, 1, 'NE1000: "%s" -> error %s', cmd, R.err);
            end
        end

        % --- Reads ---------------------------------------------------------

        function v = readOne_(obj, wire, P)
            % v = readOne_(obj, wire, P)
            % Query the pump for one parameter's live value, standing in the
            % last value it reported when a reply goes missing.
            %
            % The fallback is what keeps a dropped packet from becoming an
            % empty value. The runtime's trial-end sweep lands whatever comes
            % back straight into DATA, and everything downstream — a scatter,
            % a custom BehaviorGUI, an offline analysis — expects the parameter's
            % own type; [] there fails later and somewhere else. A stale
            % setting is still true, since nothing but a write moves it.
            % Status is the one genuinely volatile reading, so a missing
            % Status reports 'Unknown' rather than a state the pump has left.
            v = obj.queryOne_(wire, P);

            if ~isempty(v)
                if isvarname(wire)
                    obj.lastGood_.(wire) = v;
                end
                return
            end

            % busy_ still set means this read was never put on the wire: it
            % nested inside another transaction and transact_ dropped it. That
            % is a scheduling collision, not a pump that failed to answer, so
            % even Status keeps its previous value rather than reporting
            % 'Unknown' — otherwise a poll landing inside the trial-end sweep
            % would blink the operator panel's status line every trial.
            if strcmp(wire, 'Status') && ~obj.busy_
                v = 'Unknown';
            elseif isvarname(wire) && isfield(obj.lastGood_, wire)
                v = obj.lastGood_.(wire);
            elseif ~isempty(P.Values)
                v = P.Values{1};
            end
        end

        function v = queryOne_(obj, wire, P)
            % v = queryOne_(obj, wire, P)
            % One live query. Returns [] when the pump did not answer or the
            % reply did not parse; readOne_ decides what to serve instead.
            %
            % Never touch P.Value here: while connected, hw.Parameter's Value
            % getter dispatches right back into get_parameter, so using it as
            % a fallback recurses without bound. The design-time level in
            % P.Values is the safe local stand-in.
            v = [];

            switch wire
                case 'Rate'
                    R = obj.transact_('RAT');
                    tok = regexp(R.data, '^([\d.]+)', 'tokens', 'once');
                    if ~isempty(tok), v = str2double(tok{1}); end

                case 'Volume'
                    R = obj.transact_('VOL');
                    tok = regexp(R.data, '^([\d.]+)', 'tokens', 'once');
                    if ~isempty(tok), v = str2double(tok{1}); end

                case 'Diameter'
                    R = obj.transact_('DIA');
                    x = str2double(R.data);
                    if isfinite(x), v = x; end

                case 'Direction'
                    R = obj.transact_('DIR');
                    switch strtrim(R.data)
                        case 'INF', v = 'Infuse';
                        case 'WDR', v = 'Withdraw';
                        case 'STK', v = 'Sticky';
                    end

                case 'VolumeInfused'
                    d = obj.readDispensed_();
                    if ~isempty(d), v = d.inf; end

                case 'VolumeWithdrawn'
                    d = obj.readDispensed_();
                    if ~isempty(d), v = d.wdr; end

                case 'TTLTrigger'
                    code = obj.readTriggerSetup_();
                    if ~isempty(code)
                        v = ~strcmp(code, 'OF');
                    end

                case 'Status'
                    % A packet without a command is a status query.
                    R = obj.transact_('');
                    if ~isempty(R.alarm)
                        v = sprintf('Alarm:%s', R.alarm);
                    elseif ~isempty(R.status)
                        v = obj.statusLabel_(R.status);
                    end

                otherwise
                    % Triggers and anything else have no wire query; serve the
                    % design-time level.
                    if ~isempty(P.Values)
                        v = P.Values{1};
                    end
            end
        end

        function d = readDispensed_(obj)
            % d = readDispensed_(obj)
            % DIS query, cached for DispenseCacheInterval. Reply data is
            % 'I<float>W<float><units>' (manual 10.4.2).
            if ~isempty(obj.dispCacheTic_) && toc(obj.dispCacheTic_) < obj.DispenseCacheInterval
                d = obj.dispCache_;
                return
            end

            d = [];
            R = obj.transact_('DIS');
            tok = regexp(R.data, 'I\s*([\d.]+)\s*W\s*([\d.]+)\s*(UL|ML)', 'tokens', 'once');
            if isempty(tok)
                return
            end
            d = struct('inf', str2double(tok{1}), 'wdr', str2double(tok{2}), 'units', tok{3});
            obj.dispCache_ = d;
            obj.dispCacheTic_ = tic;
            obj.DispensedUnits = d.units;
        end

        function code = readTriggerSetup_(obj)
            % code = readTriggerSetup_(obj)
            % Query the pump's TTL Operational Trigger configuration and bring
            % TTLTrigger/TriggerMode into step with what it reports, so a mode
            % changed at the keypad is reflected rather than assumed. Returns
            % 'OF', a mode code, or '' when the pump did not answer.
            R = obj.transact_('TRG');
            code = upper(strtrim(R.data));
            if isempty(code)
                return
            end
            if ~strcmp(code, 'OF') && ~ismember(code, hw.NE1000.TRIGGER_MODES)
                vprintf(2, 'NE1000: pump reported an unrecognized trigger setup "%s"', code);
                code = '';
                return
            end

            obj.applyingTrigger_ = true;
            if strcmp(code, 'OF')
                obj.TTLTrigger = false;
            else
                obj.TriggerMode = code;
                obj.TTLTrigger = true;
            end
            obj.applyingTrigger_ = false;
        end

        % --- Writes ---------------------------------------------------------

        function ok = pushTrigger_(obj)
            % ok = pushTrigger_(obj)
            % Write the TTL Operational Trigger configuration: TriggerMode
            % when TTLTrigger is on, 'OF' when it is off. A no-op offline —
            % connect asserts it once the link is up.
            ok = true;
            if ~obj.linkReady_
                return
            end

            if obj.TTLTrigger
                code = obj.TriggerMode;
            else
                code = 'OF';
            end

            R = obj.transact_(sprintf('TRG%s', code));
            ok = isempty(R.err);
            if ok
                vprintf(2, 'NE1000: TTL trigger set to %s', code);
            else
                vprintf(0, 1, 'NE1000: setting the TTL trigger to %s was rejected: %s', ...
                    code, R.err);
            end
        end

        function ok = writeOne_(obj, wire, value)
            % ok = writeOne_(obj, wire, value)
            % Push one parameter value to the pump.
            ok = true;

            if iscell(value)
                if isempty(value), ok = false; return, end
                value = value{1};
            end

            switch wire
                case 'Rate'
                    % Units can only be set while stopped; when the first form
                    % is rejected mid-run, retry with the bare value, which the
                    % pump accepts while pumping (manual 10.4.1, RAT).
                    %
                    % The units form is a probe, not a promise: its '?NA' is
                    % just the pump saying "mid-run", which happens every time
                    % an operator turns the rate knob during a dispense. Only
                    % the fallback failing is worth putting in the log.
                    vs = hw.NE1000.formatFloat_(value);
                    R = obj.transact_(sprintf('RAT%s%s', vs, obj.RateUnits), Quiet = true);
                    if ~isempty(R.err)
                        R = obj.transact_(sprintf('RAT%s', vs));
                    end
                    ok = isempty(R.err);

                case 'Volume'
                    % Volume units follow the syringe diameter; never sent with
                    % the value. 0 disables the target ("continuous pumping").
                    R = obj.transact_(sprintf('VOL%s', hw.NE1000.formatFloat_(value)));
                    ok = isempty(R.err);

                case 'Diameter'
                    R = obj.transact_(sprintf('DIA%s', hw.NE1000.formatFloat_(value)));
                    ok = isempty(R.err);
                    if ok
                        obj.SyringeDiameter = double(value);
                    end

                case 'Direction'
                    code = hw.NE1000.directionCode_(value);
                    if isempty(code)
                        vprintf(0, 1, 'NE1000: "%s" is not a pumping direction (use Infuse/Withdraw)', ...
                            char(string(value)));
                        ok = false;
                        return
                    end
                    R = obj.transact_(sprintf('DIR%s', code));
                    ok = isempty(R.err);

                case 'TTLTrigger'
                    % Through the property, so a write from the trial table,
                    % the operator panel, and a paradigm's own assignment all
                    % configure the pump by the same path.
                    obj.applyingTrigger_ = true;
                    obj.TTLTrigger = logical(value);
                    obj.applyingTrigger_ = false;
                    ok = obj.pushTrigger_();

                case {'VolumeInfused', 'VolumeWithdrawn', 'Status'}
                    % Read-only on the wire; the local hw.Parameter cache has
                    % already stored the value, which is all a write can mean.

                otherwise
                    vprintf(2, 'NE1000: no wire mapping for "%s"; value kept host-side', wire);
            end
        end

        % --- Naming and labels ----------------------------------------------

        function wire = wireName_(~, P)
            % wire = wireName_(~, P)
            % Backend name for a parameter, falling back to its display name.
            wire = hw.Interface.getHardwareParameterName(P);
            if isempty(wire)
                wire = P.Name;
            end
            wire = char(wire);
        end

        function s = statusLabel_(obj, c)
            % s = statusLabel_(obj, c)
            % Operator-facing label for a prompt character.
            i = find(obj.STATUS_CHARS == c, 1);
            if isempty(i)
                s = c;
            else
                s = obj.STATUS_LABELS{i};
            end
        end

        function s = alarmLabel_(obj, c)
            % s = alarmLabel_(obj, c)
            % Operator-facing label for an alarm code.
            i = find(obj.ALARM_CHARS == c, 1);
            if isempty(i)
                s = sprintf('Unknown alarm "%s"', c);
            else
                s = obj.ALARM_LABELS{i};
            end
        end

    end  % private methods


    methods (Static)

        function spec = getCreationSpec()
            % spec = hw.NE1000.getCreationSpec()
            % Return hw.InterfaceSpec describing construction options for the
            % NE-1000 syringe pump.
            spec = hw.InterfaceSpec( ...
                char(hw.NE1000.Type), ...
                'NE-1000 Syringe Pump', ...
                'Control a New Era NE-1000 programmable syringe pump over RS-232.', ...
                [hw.InterfaceSpecOption( ...
                    'name', 'port', ...
                    'label', 'Serial Port', ...
                    'defaultValue', '', ...
                    'required', false, ...
                    'inputType', 'text', ...
                    'scope', 'interface', ...
                    'controlType', 'text', ...
                    'description', ['Serial port the pump is attached to, e.g. COM4. With a ' ...
                        'USB-RS232 converter this is the converter''s virtual port. Leave ' ...
                        'empty and enable Auto Detect to probe. The port is machine-specific, ' ...
                        'so a saved protocol may need it corrected on another rig.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'autoDetect', ...
                    'label', 'Auto Detect Port', ...
                    'defaultValue', false, ...
                    'required', false, ...
                    'inputType', 'logical', ...
                    'scope', 'interface', ...
                    'controlType', 'checkbox', ...
                    'description', ['Probe available serial ports at connect and pick the one ' ...
                        'where a pump answers a VER query at the configured address and baud ' ...
                        'rate. Slower to connect, but survives the port number changing.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'address', ...
                    'label', 'Pump Address', ...
                    'defaultValue', 0, ...
                    'required', false, ...
                    'inputType', 'numeric', ...
                    'scope', 'interface', ...
                    'controlType', 'numeric', ...
                    'description', ['Pump network address, 0-99. A single pump is address 0 ' ...
                        '(factory default). Daisy-chained pumps on one port each need a ' ...
                        'unique address, set from the pump''s Setup menu.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'baudRate', ...
                    'label', 'Baud Rate', ...
                    'defaultValue', 19200, ...
                    'required', false, ...
                    'inputType', 'numeric', ...
                    'scope', 'interface', ...
                    'controlType', 'dropdown', ...
                    'choices', {{'19200', '9600', '2400', '1200', '300'}}, ...
                    'description', ['Must match the pump''s Setup baud rate. 19200 (the pump''s ' ...
                        'default) is right for most rigs; drop lower only for long or ' ...
                        'electrically noisy cables.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'syringeDiameter', ...
                    'label', 'Syringe Diameter (mm)', ...
                    'defaultValue', 0, ...
                    'required', false, ...
                    'inputType', 'numeric', ...
                    'scope', 'interface', ...
                    'controlType', 'numeric', ...
                    'description', ['Inside diameter of the loaded syringe in mm (0.1-50), ' ...
                        'pushed to the pump at connect. Every rate and volume the pump ' ...
                        'computes scales with this. 0 keeps the value stored in the pump. ' ...
                        'See the manual''s Syringe Diameters table (sec. 12.7).']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'rateUnits', ...
                    'label', 'Rate Units', ...
                    'defaultValue', 'MH', ...
                    'required', false, ...
                    'inputType', 'text', ...
                    'scope', 'interface', ...
                    'controlType', 'dropdown', ...
                    'choices', {{'MH', 'MM', 'UH', 'UM'}}, ...
                    'description', ['Units attached when writing the Rate parameter: MH=mL/hr, ' ...
                        'MM=mL/min, UH=µL/hr, UM=µL/min.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'ttlTrigger', ...
                    'label', 'TTL Trigger Control', ...
                    'defaultValue', false, ...
                    'required', false, ...
                    'inputType', 'logical', ...
                    'scope', 'interface', ...
                    'controlType', 'checkbox', ...
                    'description', ['Let the pump''s TTL Operational Trigger input (DB-9 pin 2) ' ...
                        'start and stop it, for hardware-timed reward with no host round trip. ' ...
                        'Asserted at connect either way, so an unchecked box disables a trigger ' ...
                        'left enabled at the keypad. The trigger mode (level, foot switch, ' ...
                        'start-only, ...) is set in code through the interface''s TriggerMode ' ...
                        'property and defaults to LE (rising edge starts, falling edge stops).'])], ...
                @(opts) hw.NE1000(char(hw.NE1000.optField_(opts, 'port', '')), ...
                    BaudRate        = double(string(hw.NE1000.optField_(opts, 'baudRate', 19200))), ...
                    Address         = double(string(hw.NE1000.optField_(opts, 'address', 0))), ...
                    SyringeDiameter = double(string(hw.NE1000.optField_(opts, 'syringeDiameter', 0))), ...
                    RateUnits       = char(hw.NE1000.optField_(opts, 'rateUnits', 'MH')), ...
                    TTLTrigger      = logical(hw.NE1000.optField_(opts, 'ttlTrigger', false)), ...
                    AutoDetect      = logical(hw.NE1000.optField_(opts, 'autoDetect', false))));
        end

        function port = findPumpPort(options)
            % port = hw.NE1000.findPumpPort(Name=Value)
            % Probe available serial ports for a pump that answers VER.
            %
            % Name=Value
            %   BaudRate (double) - Default 19200
            %   Address (double)  - Pump network address. Default 0
            %   Timeout (double)  - Per-port timeout (s). Default 1
            %
            % Returns:
            %   port - Matching port name, or '' when none answered.
            arguments
                options.BaudRate (1,1) double = 19200
                options.Address (1,1) double = 0
                options.Timeout (1,1) double = 1
            end

            port = '';
            try
                candidates = cellstr(serialportlist('available'));
            catch
                candidates = {};
            end

            for i = 1:numel(candidates)
                sp = [];
                try
                    sp = serialport(candidates{i}, options.BaudRate, ...
                        DataBits = 8, StopBits = 1, Parity = 'none', ...
                        FlowControl = 'none', Timeout = options.Timeout);
                    configureTerminator(sp, 3, 'CR');
                    flush(sp, 'input');

                    % Kick a Safe-mode pump back to Basic before asking.
                    write(sp, uint8([2 8 'SAF0' 85 67 3]), 'uint8');
                    pause(0.1);
                    flush(sp, 'input');

                    writeline(sp, sprintf('%dVER', options.Address));
                    raw = char(readline(sp));
                    R = hw.NE1000.parseResponse_(raw);
                    if R.ok && startsWith(R.data, 'NE')
                        port = candidates{i};
                    end
                catch
                    % A port held by another process, or a device that does not
                    % answer, is simply not our pump.
                end

                try
                    if ~isempty(sp) && isvalid(sp)
                        delete(sp);
                    end
                catch
                end

                if ~isempty(port)
                    return
                end
            end
        end

        function R = parseResponse_(raw)
            % R = hw.NE1000.parseResponse_(raw)
            % Decode one reply payload: [<STX>]<addr><status>[data][<ETX>].
            %
            % Returns the same struct shape as transact_: ok, status, alarm,
            % data, err. Static and pure so a smoke test can exercise the
            % parser with no pump attached.
            R = struct('ok', false, 'status', '', 'alarm', '', 'data', '', 'err', '');

            raw = char(raw);
            raw(raw == hw.NE1000.STX | raw == hw.NE1000.ETX) = [];
            if isempty(raw)
                return
            end

            % Leading digits are the responding pump's network address.
            i = 1;
            while i <= numel(raw) && raw(i) >= '0' && raw(i) <= '9'
                i = i + 1;
            end
            body = raw(i:end);
            if isempty(body)
                return
            end

            if startsWith(body, 'A?')
                % Alarm status: A?<alarm type>
                if numel(body) >= 3
                    R.alarm = body(3);
                    R.data = body(4:end);
                    R.ok = true;
                end
                return
            end

            if ~ismember(body(1), hw.NE1000.STATUS_CHARS)
                return
            end
            R.status = body(1);
            R.data = strtrim(body(2:end));
            R.ok = true;

            % A command error rides in the data field as '?[code]'.
            if startsWith(R.data, '?')
                R.err = R.data(2:end);
                if isempty(R.err)
                    R.err = 'unrecognized command';
                end
                R.data = '';
            end
        end

        function tf = isQuery_(cmd)
            % tf = hw.NE1000.isQuery_(cmd)
            % True for the commands that only report state, and so may be
            % safely resent after a dropped reply. Everything else — RUN, STP,
            % CLD, and every setter — changes the pump, and a command whose
            % reply went missing may still have been performed.
            cmd = char(cmd);
            tf = isempty(cmd) || ismember(cmd, {'VER', 'RAT', 'VOL', 'DIA', 'DIR', 'DIS', 'TRG'});
        end

        function s = formatFloat_(v)
            % s = hw.NE1000.formatFloat_(v)
            % Render a number within the pump's "maximum of 4 digits plus 1
            % decimal point" command grammar (manual 10.2.1), keeping as much
            % precision as those 4 digits allow.
            v = abs(double(v));
            if v >= 1000
                s = sprintf('%.0f', v);
            elseif v >= 100
                s = sprintf('%.1f', v);
            elseif v >= 10
                s = sprintf('%.2f', v);
            else
                s = sprintf('%.3f', v);
            end
        end

        function code = directionCode_(value)
            % code = hw.NE1000.directionCode_(value)
            % Map a direction value to the pump's DIR argument, '' when the
            % value names no direction. Accepts the friendly names, the wire
            % codes, and 0/1 (0 = infuse, 1 = withdraw).
            code = '';
            if isnumeric(value) || islogical(value)
                if isempty(value), return, end
                if value(1)
                    code = 'WDR';
                else
                    code = 'INF';
                end
                return
            end
            switch upper(strtrim(char(string(value))))
                case {'INF', 'INFUSE'},           code = 'INF';
                case {'WDR', 'WITHDRAW'},         code = 'WDR';
                case {'REV', 'REVERSE'},          code = 'REV';
                case {'STK', 'STICKY'},           code = 'STK';
            end
        end

        function v = optField_(opts, name, default)
            % v = hw.NE1000.optField_(opts, name, default)
            % Read opts.(name) when present and non-empty, else return default.
            % Lets getCreationSpec's factory tolerate an options struct saved
            % before a newer option existed.
            v = default;
            if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
                v = opts.(name);
            end
        end

    end  % Static methods

end


function specs = local_parameterSpecs_(rateUnits)
% specs = local_parameterSpecs_(rateUnits)
% Describe every parameter an NE-1000 interface exposes.
%
% VISIBLE / ACCESS MATRIX (see hw.Bpod.populateModule_ for the derivation):
%   trial table = Visible && Access ~= 'Read'
%   DATA sweep  = Visible && ~isTrigger && Access ~= 'Write'
% So:
%   Rate, Volume                    - Visible, 'Any':  trial config AND recorded in DATA.
%   VolumeInfused, VolumeWithdrawn  - Visible, 'Read': recorded in DATA only.
%   Direction, Diameter, Status     - invisible: operator-facing via
%                                     set_parameter/get_parameter only.
%   Start, Stop, ClearVolume        - invisible triggers for gui.Triggers and
%                                     custom behavior GUIs.

switch rateUnits
    case 'UM', rateLabel = 'uL/min'; volLabel = 'uL';
    case 'MM', rateLabel = 'mL/min'; volLabel = 'mL';
    case 'UH', rateLabel = 'uL/hr';  volLabel = 'uL';
    otherwise, rateLabel = 'mL/hr';  volLabel = 'mL';
end

specs = local_spec_();

specs(end + 1) = local_spec_('Rate', 1, ...
    struct('Type', 'Float', 'Access', 'Any', 'Visible', true, ...
           'Min', 0, 'Unit', rateLabel, ...
           'Description', "Pumping rate, in the interface's RateUnits. The valid range depends on the syringe diameter (manual sec. 12.7); an out-of-range write is rejected by the pump and logged."));

specs(end + 1) = local_spec_('Volume', 0, ...
    struct('Type', 'Float', 'Access', 'Any', 'Visible', true, ...
           'Min', 0, 'Unit', volLabel, ...
           'Description', "Volume to be dispensed per Start. 0 disables the target: the pump runs continuously until Stop. Units follow the syringe diameter (uL below 14 mm, mL at or above)."));

specs(end + 1) = local_spec_('Direction', 'Infuse', ...
    struct('Type', 'String', 'Access', 'Any', 'Visible', false, ...
           'Description', "Pumping direction: Infuse or Withdraw (also accepts Reverse and Sticky). Cannot be changed while pumping toward a non-zero Volume target."));

specs(end + 1) = local_spec_('Diameter', 0, ...
    struct('Type', 'Float', 'Access', 'Any', 'Visible', false, ...
           'Min', 0, 'Max', 50, 'Unit', 'mm', ...
           'Description', "Syringe inside diameter in mm (0.1-50). Settable only while stopped. Changing it switches the pump's default volume units and resets the dispensed-volume accumulators."));

specs(end + 1) = local_spec_('VolumeInfused', 0, ...
    struct('Type', 'Float', 'Access', 'Read', 'Visible', true, ...
           'Unit', volLabel, ...
           'Description', "Accumulated infused volume reported by the pump (DIS query). Reset by the ClearVolume trigger, a diameter change, or pump power-up."));

specs(end + 1) = local_spec_('VolumeWithdrawn', 0, ...
    struct('Type', 'Float', 'Access', 'Read', 'Visible', true, ...
           'Unit', volLabel, ...
           'Description', "Accumulated withdrawn volume reported by the pump (DIS query)."));

specs(end + 1) = local_spec_('TTLTrigger', false, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, ...
           'Description', "Whether the pump's TTL Operational Trigger input (DB-9 pin 2) may start and stop it. Enabling writes the interface's TriggerMode ('LE' by default), disabling writes 'TRG OF'. The mode itself is a property of the interface, not a parameter: it follows the rig's wiring rather than the trial."));

specs(end + 1) = local_spec_('Status', 'Stopped', ...
    struct('Type', 'String', 'Access', 'Read', 'Visible', false, ...
           'Description', "Live pump state from the reply prompt character: Infusing, Withdrawing, Stopped, Paused, TimedPause, TriggerWait, Purging, or Alarm:<code>. 'Unknown' when the pump did not answer the query."));

specs(end + 1) = local_spec_('Start', false, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, 'isTrigger', true, ...
           'Description', "Starts the Pumping Program (RUN). Resumes from a pause, otherwise starts from Phase 1. With Volume set, the pump stops itself after dispensing that volume."));

specs(end + 1) = local_spec_('Stop', false, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, 'isTrigger', true, ...
           'Description', "Stops the pump (STP). A run in progress is paused; a second Stop resets the Pumping Program to Phase 1."));

specs(end + 1) = local_spec_('ClearVolume', false, ...
    struct('Type', 'Boolean', 'Access', 'Any', 'Visible', false, 'isTrigger', true, ...
           'Description', "Zeros both dispensed-volume accumulators (CLD INF + CLD WDR). Only valid while the pump is stopped."));

end


function s = local_spec_(name, value, options)
% s = local_spec_(name, value, options)
% Build one parameter spec, or the empty spec array when called with no
% arguments. The field order is fixed so specs always concatenate.
fields = {'Name', 'Value', 'Options'};

if nargin == 0
    args = [fields; repmat({{}}, 1, numel(fields))];
    s = struct(args{:});
    return
end

s = struct('Name', char(name), 'Value', value, 'Options', options);

end
