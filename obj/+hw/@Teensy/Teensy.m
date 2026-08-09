classdef Teensy < hw.Interface

    % obj = hw.Teensy(port, Name=Value)
    % Hardware interface for a Teensy 4.x microcontroller running EPsychTeensy firmware.
    %
    % Communicates over USB serial (CDC) using a newline-terminated ASCII
    % protocol. The board owns the millisecond-scale parts of a trial —
    % debounced input detection, output pulse timing, and (optionally) the
    % trial contingency itself — so response latencies do not inherit MATLAB
    % timer jitter.
    %
    % Firmware protocol notes (these shape the implementation):
    %   - Every command produces exactly ONE reply line, or a BEGIN/END block.
    %     The firmware never emits unsolicited output, which is what keeps the
    %     synchronous request/response model valid.
    %   - Input events are timestamped on-device to the microsecond but
    %     DELIVERED by polling: SNAP carries latched state for the per-tick
    %     poll, EVT? drains the precise timestamped history.
    %   - Values may not contain spaces (the SETM grammar is space-delimited);
    %     arrays are comma-separated with no spaces.
    %
    % Parameters
    %   port    - Serial port name, e.g. 'COM6' or '/dev/ttyACM0'. Empty with
    %             AutoDetect=true scans for a board by boot greeting.
    %
    % Name=Value options
    %   BaudRate (double)     - Nominal baud; ignored by USB CDC. Default 115200
    %   Timeout (double)      - Transaction timeout in seconds. Default 1
    %   Connect (logical)     - Connect on construction. Default true
    %   AutoDetect (logical)  - Scan ports for the board when connecting. Default false
    %   DeviceSerial (char)   - Expected board serial; used to disambiguate during AutoDetect
    %
    % Properties
    %   Port, BaudRate, Timeout   - Connection settings.
    %   IsConnected               - True when the port is open and the board handshook.
    %   Module                    - Single hw.Module holding the board's parameters.
    %   mode                      - Current hw.DeviceState.
    %   FirmwareVersion, BoardType, ProtocolVersion - Reported by the board at connect.
    %   SnapshotInterval          - TTL (s) on the batched read cache.
    %   ModePollInterval          - Min seconds between live mode queries.
    %   CoalesceWrites            - Batch writes and flush them at the next trigger or read.
    %
    % Methods
    %   connect, disconnect, close_interface - Connection management.
    %   get_parameter, set_parameter - Named parameter I/O.
    %   trigger - Pulse a trigger parameter; returns a `now` timestamp.
    %   flushWrites - Force any coalesced writes out to the board.
    %   drainEvents - Drain the board's timestamped event queue.
    %   syncClock - Estimate the board-clock to host-clock offset.
    %   setModules - Replace the Module array while offline.
    %
    % Usage
    %   iface = hw.Teensy('COM6');
    %   iface = hw.Teensy('', AutoDetect=true);
    %
    %   % Offline construction for serialization round-trip
    %   iface = hw.Teensy('COM6', Connect=false);
    %
    % See also: documentation/hw/hw_Interface.md, documentation/hw/hw_Interface_Tutorial.md,
    %           hw.Module, hw.Parameter, firmware/EPsychTeensy


    properties
        Port (1,:) char = ''             % serial port name, e.g. 'COM6'
        BaudRate (1,1) double = 115200   % nominal only; USB CDC ignores it
        Timeout (1,1) double = 1         % transaction timeout in seconds
        HW = []                          % serialport handle (also required by hw.Parameter)

        AutoDetect (1,1) logical = false % scan ports for the board on connect
        DeviceSerial (1,:) char = ''     % expected board serial number

        % Timing knobs (public so tests can shorten them).
        BootDelay (1,1) double = 1.5     % seconds after opening the port, for USB re-enumeration
        ModePollInterval (1,1) double = 0.25   % min seconds between live mode queries

        % TTL on the batched read cache. Sized well under the runtime's 10 ms
        % tick so a fresh tick always re-polls. If a trial-end sweep outlives
        % it the sweep spans two SNAPs, which is harmless here: the firmware
        % latches trial results when it raises TrialComplete and holds them
        % until the next ResetTrig, so both snapshots report the same values.
        SnapshotInterval (1,1) double = 0.005

        % Batch writes and flush them at the next trigger or read. The runtime
        % dispatches a trial as reset -> k writes -> trigger, so the flush lands
        % exactly at the trigger and k round-trips collapse into one. Every tick
        % also performs a read, so worst-case unflushed latency is one tick.
        CoalesceWrites (1,1) logical = true
    end

    properties (SetObservable, AbortSet)
        mode  % Current device state (hw.DeviceState)
    end

    properties (Dependent)
        % True when the port is open and the board handshook. Deliberately
        % undecorated: MATLAB rejects size/class validation on a property
        % inherited from an abstract declaration.
        IsConnected
    end

    properties (SetAccess = protected)
        Module                            % hw.Module array
        FirmwareVersion (1,:) char = ''   % FW= field reported by ID?
        BoardType (1,:) char = ''         % BOARD= field reported by ID?
        ProtocolVersion (1,1) double = 0  % PROTO= field reported by ID?
        BoxIDs (1,:) double = []          % box identifiers the firmware serves
        ClockOffset (1,1) double = 0      % posix seconds - board micros/1e6
        ClockUncertainty (1,1) double = inf % half the best observed round-trip (s)
    end

    properties (Constant)
        Type = "Teensy"

        % Wire protocol this class speaks. connect() warns when the board
        % reports a different major, because a mismatched grammar fails as
        % garbled replies rather than as a clean error.
        PROTOCOL_VERSION = 1

        % Longest command line the firmware's fixed input buffer accepts.
        % flushWrites() chunks SETM below this. Keep in sync with
        % firmware/EPsychTeensy/Config.h LINE_BUFFER_LEN.
        MAX_LINE_LENGTH = 240
    end

    properties (Access = protected)
        % State reachable by test subclasses (tmp/Teensy_Mock).
        linkReady_ (1,1) logical = false   % port open and handshake accepted
        modeCache_ (1,1) hw.DeviceState = hw.DeviceState.Idle
        modeCacheTic_ = []                 % tic of last live mode query; [] forces a query
        snapshot_ = struct()               % wire name -> last SNAP value
        snapshotTic_ = []                  % tic of last SNAP; [] forces a refresh
        pendingWrites_ = {}                % Nx2 cell {wireName, formattedValue}
        eventBuffer_ = zeros(0, 3)         % [boardMicros, channelIndex, value]
    end


    methods

        function obj = Teensy(port, options)
            % obj = hw.Teensy(port, Name=Value)
            % Construct a Teensy interface and optionally connect.
            %
            % Parameters
            %   port - Serial port name. Default '' (requires AutoDetect).
            % Name=Value
            %   BaudRate (double)    - Nominal baud rate. Default 115200
            %   Timeout (double)     - Transaction timeout (s). Default 1
            %   Connect (logical)    - Connect on construction. Default true
            %   AutoDetect (logical) - Scan ports for the board. Default false
            %   DeviceSerial (char)  - Expected board serial number.
            arguments
                port (1,:) char = ''
                options.BaudRate (1,1) double = 115200
                options.Timeout (1,1) double = 1
                options.Connect (1,1) logical = true
                options.AutoDetect (1,1) logical = false
                options.DeviceSerial (1,:) char = ''
                options.BootDelay (1,1) double = 1.5
            end

            obj.Port = port;
            obj.BaudRate = options.BaudRate;
            obj.Timeout = options.Timeout;
            obj.AutoDetect = options.AutoDetect;
            obj.DeviceSerial = options.DeviceSerial;
            obj.BootDelay = options.BootDelay;
            obj.Module = hw.Module.empty(1, 0);

            if options.Connect
                obj.connect();
            end
        end

        function delete(obj)
            % delete(obj)
            % Release the serial port when the interface is cleared.
            obj.close_interface();
        end

        function connect(obj)
            % connect(obj)
            % Open the serial port, handshake with the firmware, and build the
            % module and parameter table. Safe to call when already connected.
            if obj.IsConnected
                return
            end
            obj.setup_interface();
        end

        function disconnect(obj)
            % disconnect(obj)
            % Close the serial port. Called by RunExpt.onCloseRequest.
            obj.close_interface();
        end

        function tf = get.IsConnected(obj)
            % tf = get.IsConnected(obj)
            % True when the port handle is live and the firmware handshook.
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
            % Current device state, throttled to ModePollInterval.
            %
            % RunExpt.PsychTimerRunTime reads this on every 10 ms timer tick and
            % stops the session when any interface reports Idle, so this must be
            % cheap AND must never fabricate Idle from a failed query.
            if ~obj.IsConnected
                m = obj.modeCache_;
                return
            end
            if ~isempty(obj.modeCacheTic_) && toc(obj.modeCacheTic_) < obj.ModePollInterval
                m = obj.modeCache_;
                return
            end
            m = obj.queryMode_();
        end

        function set.mode(obj, m)
            % set.mode(obj, m)
            % Push a new device state to the board.
            m = hw.DeviceState(m);
            obj.modeCache_ = m;
            obj.modeCacheTic_ = tic;
            if ~obj.IsConnected
                return
            end
            obj.flushWrites();
            reply = obj.transact_(sprintf('MODE %d', int8(m)));
            if ~startsWith(reply, 'OK')
                vprintf(0, 1, 'Teensy: setting mode to %s was rejected: %s', char(m), reply);
            end
            obj.snapshotTic_ = [];
        end

        function setModules(obj, modules)
            % setModules(obj, modules)
            % Replace the Module array. Not on the hw.Interface contract but
            % required by Protocol.createInterfaceFromStruct_ and the
            % ProtocolDesigner module editor, which both build modules
            % externally against an offline interface.
            arguments
                obj
                modules (1,:) hw.Module
            end
            if obj.IsConnected
                error('hw:Teensy:ModulesWhileConnected', ...
                    'Disconnect before replacing modules on a live Teensy interface.');
            end
            obj.Module = modules;
        end

        % --- Parameter I/O -------------------------------------------------

        function value = get_parameter(obj, name, options)
            % value = get_parameter(obj, name, Name=Value)
            % Read one or more parameters, preserving the requested order.
            %
            % Reads are served from a snapshot cache refreshed by a single SNAP
            % command, so the runtime's trial-end sweep over every readable
            % parameter costs one round-trip rather than N.
            %
            % Parameters
            %   name - Parameter name(s) or hw.Parameter handle(s).
            % Name=Value
            %   includeInvisible (logical)        - Include hidden parameters. Default true
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

            if ~obj.IsConnected
                % Offline: serve the locally cached value so a protocol can be
                % edited and previewed with no board attached.
                for i = 1:numel(P)
                    value{i} = P(i).Value;
                end
            else
                obj.flushWrites();
                obj.refreshSnapshot_();
                for i = 1:numel(P)
                    wire = obj.wireName_(P(i));
                    field = matlab.lang.makeValidName(wire);
                    if isfield(obj.snapshot_, field)
                        value{i} = obj.snapshot_.(field);
                    else
                        % Not carried by SNAP (large buffers, or a name the
                        % board does not publish). Fall back to a direct read.
                        value{i} = obj.readOne_(wire);
                    end
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
            % With CoalesceWrites=true the write is buffered and flushed as one
            % SETM line at the next trigger or read.
            %
            % Parameters
            %   name  - Parameter name(s) or hw.Parameter handle(s).
            %   value - Scalar (expanded across all targets) or per-target values.
            %
            % Returns:
            %   result - True when the write was accepted or buffered.
            if isa(name, 'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name, includeInvisible = true);
            end

            if isempty(P)
                result = false;
                return
            end

            % The SETM grammar carries space-delimited scalars; a stimulus has
            % no representation on that wire and the firmware has no waveform
            % output. Named here so the skip reads as intentional rather than
            % surfacing as formatValue_'s generic "unsupported value type" on
            % every trial.
            if hw.Interface.isStimulusValue(value)
                vprintf(2,['hw.Teensy: "%s" holds a stimulus, which the firmware ' ...
                    'command grammar cannot express; value kept host-side'], P(1).Name)
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
                wire = obj.wireName_(P(i));
                valStr = obj.formatValue_(P(i), value{i});
                if isempty(valStr)
                    result = false;
                    continue
                end
                if obj.CoalesceWrites
                    obj.queueWrite_(wire, valStr);
                else
                    reply = obj.transact_(sprintf('SET %s %s', wire, valStr));
                    if ~startsWith(reply, 'OK')
                        vprintf(0, 1, 'Teensy: SET %s %s failed: %s', wire, valStr, reply);
                        result = false;
                    end
                end
            end

            % Any write invalidates the read cache.
            obj.snapshotTic_ = [];
        end

        function t = trigger(obj, name)
            % t = trigger(obj, name)
            % Pulse one or more trigger parameters.
            %
            % Returns:
            %   t - Timestamp as a `now` serial date number. hw.Parameter.Trigger
            %       assigns this straight into lastUpdated (1,1) double, so it
            %       must be a double and not a datetime.
            if isa(name, 'hw.Parameter')
                P = name;
            else
                % all_parameters (which find_parameter delegates to) includes
                % triggers by default, so no extra option is needed here.
                P = obj.find_parameter(name, includeInvisible = true);
            end

            if isempty(P) || ~obj.IsConnected
                t = now;
                return
            end

            % Flush first: the runtime dispatches reset -> writes -> trigger, so
            % this is where a trial's parameter writes reach the board, and they
            % must land before the trial starts.
            obj.flushWrites();

            for i = 1:numel(P)
                wire = obj.wireName_(P(i));
                reply = obj.transact_(sprintf('TRG %s', wire));
                if ~startsWith(reply, 'OK')
                    vprintf(0, 1, 'Teensy: TRG %s failed: %s', wire, reply);
                end
            end
            t = now;

            obj.snapshotTic_ = [];
        end

        function snapshotInvalidate(obj)
            % snapshotInvalidate(obj)
            % Discard the batched read cache so the next read hits the board.
            %
            % Reads within SnapshotInterval are normally served from cache. Call
            % this when device state may have changed behind the interface's
            % back, or in a test that needs a guaranteed fresh read.
            obj.snapshotTic_ = [];
        end

        function flushWrites(obj)
            % flushWrites(obj)
            % Send any coalesced writes as one or more SETM lines.
            if isempty(obj.pendingWrites_) || ~obj.IsConnected
                obj.pendingWrites_ = {};
                return
            end

            pending = obj.pendingWrites_;
            obj.pendingWrites_ = {};

            chunk = 'SETM';
            for i = 1:size(pending, 1)
                piece = sprintf(' %s=%s', pending{i, 1}, pending{i, 2});
                if numel(chunk) + numel(piece) > obj.MAX_LINE_LENGTH
                    obj.sendSetM_(chunk);
                    chunk = 'SETM';
                end
                chunk = [chunk piece];
            end
            if ~strcmp(chunk, 'SETM')
                obj.sendSetM_(chunk);
            end
        end

        % --- Events and clock ----------------------------------------------

        function E = drainEvents(obj)
            % E = drainEvents(obj)
            % Drain the board's timestamped event queue.
            %
            % Returns:
            %   E - Nx3 double [boardMicros, channelIndex, value]. Board micros
            %       map onto host time as boardMicros/1e6 + ClockOffset.
            E = zeros(0, 3);
            if ~obj.IsConnected
                return
            end
            obj.flushWrites();
            lines = obj.transactBlock_('EVT?', 'EVT');
            if isempty(lines)
                obj.eventBuffer_ = E;
                return
            end

            % Resolve names to parameter indices once per drain rather than per
            % event; a busy trial can return hundreds of rows.
            channels = obj.channelMap_();

            E = zeros(numel(lines), 3);
            kept = 0;
            for i = 1:numel(lines)
                tok = strsplit(strtrim(lines{i}));
                if numel(tok) < 4 || ~strcmp(tok{1}, 'E')
                    continue
                end
                idx = 0;
                hit = find(strcmp(channels, tok{3}), 1);
                if ~isempty(hit)
                    idx = hit;
                end
                kept = kept + 1;
                E(kept, :) = [str2double(tok{2}), idx, str2double(tok{4})];
            end
            E = E(1:kept, :);
            obj.eventBuffer_ = E;
        end

        function [offset, uncertainty] = syncClock(obj, nSamples)
            % [offset, uncertainty] = syncClock(obj, nSamples)
            % Estimate the board-clock to host-clock offset.
            %
            % Brackets each SYNC with a host timestamp and keeps the sample with
            % the smallest round-trip, the same best-of rule NTP uses, because
            % the minimum round-trip is the least contaminated by USB scheduling.
            %
            % Parameters
            %   nSamples - Number of SYNC exchanges. Default 11.
            %
            % Returns:
            %   offset      - Seconds to add to boardMicros/1e6 to reach posix time.
            %   uncertainty - Half the best round-trip, in seconds.
            arguments
                obj
                nSamples (1,1) double {mustBePositive, mustBeInteger} = 11
            end

            offset = obj.ClockOffset;
            uncertainty = obj.ClockUncertainty;
            if ~obj.IsConnected
                return
            end

            bestRT = inf;
            for i = 1:nSamples
                t0 = posixtime(datetime('now', TimeZone = 'UTC'));
                reply = obj.transact_('SYNC');
                t1 = posixtime(datetime('now', TimeZone = 'UTC'));
                tok = strsplit(strtrim(reply));
                if numel(tok) < 2 || ~strcmp(tok{1}, 'SYNC')
                    continue
                end
                boardSeconds = str2double(tok{2}) / 1e6;
                roundTrip = t1 - t0;
                if roundTrip < bestRT
                    bestRT = roundTrip;
                    offset = (t0 + t1) / 2 - boardSeconds;
                    uncertainty = roundTrip / 2;
                end
            end

            obj.ClockOffset = offset;
            obj.ClockUncertainty = uncertainty;
            vprintf(2, 'Teensy: clock offset %.6f s (+/- %.6f s)', offset, uncertainty);
        end

        % --- Diagnostics ---------------------------------------------------

        function results = selfTest(obj, options)
            % results = selfTest(obj, Invasive=false)
            % Pre-flight diagnostics for epsych.SelfTest. Never throws.
            %
            % Non-invasive checks make no hardware calls at all, so they are safe
            % to run against a live session. The invasive pass may open the port
            % and must restore the connection state it found.
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
                    results(end + 1) = hw.Interface.selfTestResult('Teensy Port', 'info', ...
                        'No port configured; AutoDetect will scan on connect.');
                else
                    results(end + 1) = hw.Interface.selfTestResult('Teensy Port', 'fail', ...
                        'No serial port configured.', ...
                        Remedy = 'Set the Port option in ProtocolDesigner, or enable AutoDetect.');
                end
            elseif ismember(obj.Port, available) || obj.IsConnected
                results(end + 1) = hw.Interface.selfTestResult('Teensy Port', 'pass', ...
                    sprintf('Port %s is present.', obj.Port));
            else
                results(end + 1) = hw.Interface.selfTestResult('Teensy Port', 'fail', ...
                    sprintf('Port %s is not among the available serial ports.', obj.Port), ...
                    Detail = sprintf('Available: %s', strjoin(available, ', ')), ...
                    Remedy = 'Check the USB cable and that the board is powered and flashed.');
            end

            if ~options.Invasive
                results(end + 1) = hw.Interface.selfTestResult('Teensy Handshake', 'skip', ...
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
                    results(end + 1) = hw.Interface.selfTestResult('Teensy Handshake', 'fail', ...
                        'Could not open a connection to the board.', ...
                        Remedy = 'Verify the port, then re-flash EPsychTeensy firmware if needed.');
                elseif obj.ProtocolVersion ~= obj.PROTOCOL_VERSION
                    results(end + 1) = hw.Interface.selfTestResult('Teensy Handshake', 'warn', ...
                        sprintf('Board speaks protocol %d; this class speaks %d.', ...
                            obj.ProtocolVersion, obj.PROTOCOL_VERSION), ...
                        Remedy = 'Re-flash the board with the firmware in firmware/EPsychTeensy.');
                else
                    results(end + 1) = hw.Interface.selfTestResult('Teensy Handshake', 'pass', ...
                        sprintf('%s, firmware %s, protocol %d.', ...
                            obj.BoardType, obj.FirmwareVersion, obj.ProtocolVersion));
                end

                if ~wasConnected
                    obj.disconnect();
                end
            catch ME
                results(end + 1) = hw.Interface.selfTestResult('Teensy Handshake', 'fail', ...
                    'Handshake raised an error.', ...
                    Detail = ME.message, ...
                    Remedy = 'Close any serial terminal holding the port, then retry.');
                try
                    if ~wasConnected
                        obj.disconnect();
                    end
                catch
                end
            end
        end

        function tf = canReadHardwareParameters(obj, module)
            % tf = canReadHardwareParameters(obj, module)
            % True when the board's parameter table can be read via DESC?.
            %
            % Requires either a live connection or a configured port to open
            % temporarily. This is what enables ProtocolDesigner's "Read HW
            % Params" button for this backend.
            tf = obj.IsConnected || ~isempty(obj.Port) || obj.AutoDetect;
            if nargin > 1 && ~isempty(module) && ~isa(module, 'hw.Module')
                tf = false;
            end
        end

    end  % public methods


    methods
        % Implemented in a separate file (overrides hw.Interface.readHardwareParameters)
        [tf, msg] = readHardwareParameters(obj, module, options)
    end

    methods (Access = protected)
        % Implemented in separate files
        setup_interface(obj)
        populateModuleParametersFromDescriptor(obj, module, descriptorLines, options)
    end


    methods (Static)

        function spec = getCreationSpec()
            % spec = hw.Teensy.getCreationSpec()
            % Return hw.InterfaceSpec describing construction options for Teensy.
            spec = hw.InterfaceSpec( ...
                char(hw.Teensy.Type), ...
                'Teensy Microcontroller', ...
                'Connect to a Teensy 4.x running EPsychTeensy firmware over USB serial.', ...
                [hw.InterfaceSpecOption( ...
                    'name', 'port', ...
                    'label', 'Serial Port', ...
                    'defaultValue', '', ...
                    'required', false, ...
                    'inputType', 'text', ...
                    'scope', 'interface', ...
                    'controlType', 'text', ...
                    'description', ['Serial port the board enumerates on, e.g. COM6 or ' ...
                        '/dev/ttyACM0. Leave empty and enable Auto Detect to scan. The port ' ...
                        'is machine-specific, so a saved protocol may need it corrected on ' ...
                        'another rig.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'autoDetect', ...
                    'label', 'Auto Detect Port', ...
                    'defaultValue', false, ...
                    'required', false, ...
                    'inputType', 'logical', ...
                    'scope', 'interface', ...
                    'controlType', 'checkbox', ...
                    'description', ['Scan available serial ports at connect and pick the one ' ...
                        'whose boot greeting identifies an EPsychTeensy board. Slower to ' ...
                        'connect, but survives the port number changing between sessions.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'deviceSerial', ...
                    'label', 'Device Serial', ...
                    'defaultValue', '', ...
                    'required', false, ...
                    'inputType', 'text', ...
                    'scope', 'interface', ...
                    'controlType', 'text', ...
                    'description', ['Expected board serial number. When set, Auto Detect ' ...
                        'accepts only this board — the way to keep two Teensys in one rig ' ...
                        'from being swapped.']), ...
                hw.InterfaceSpecOption( ...
                    'name', 'baudRate', ...
                    'label', 'Baud Rate', ...
                    'defaultValue', 115200, ...
                    'required', false, ...
                    'inputType', 'numeric', ...
                    'scope', 'interface', ...
                    'controlType', 'numeric', ...
                    'description', ['Nominal baud rate. Teensy native USB ignores this and ' ...
                        'always runs at full USB speed; it matters only behind a USB-serial ' ...
                        'converter.'])], ...
                @(opts) hw.Teensy(char(hw.Teensy.optField_(opts, 'port', '')), ...
                    BaudRate     = double(hw.Teensy.optField_(opts, 'baudRate', 115200)), ...
                    AutoDetect   = logical(hw.Teensy.optField_(opts, 'autoDetect', false)), ...
                    DeviceSerial = char(hw.Teensy.optField_(opts, 'deviceSerial', ''))));
        end

        function port = findBoardPort(options)
            % port = hw.Teensy.findBoardPort(Name=Value)
            % Scan available serial ports for an EPsychTeensy board.
            %
            % Opens each candidate, waits out the USB CDC boot delay, and looks
            % for the firmware's boot greeting. Mirrors
            % peripherals.NanoMotorControl.findControllerPort.
            %
            % Name=Value
            %   BaudRate (double)   - Default 115200
            %   Timeout (double)    - Per-port timeout (s). Default 1
            %   BootDelay (double)  - Settle time after opening (s). Default 1.5
            %   DeviceSerial (char) - Accept only this board serial. Default '' (any)
            %
            % Returns:
            %   port - Matching port name, or '' when none matched.
            arguments
                options.BaudRate (1,1) double = 115200
                options.Timeout (1,1) double = 1
                options.BootDelay (1,1) double = 1.5
                options.DeviceSerial (1,:) char = ''
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
                    sp = serialport(candidates{i}, options.BaudRate, Timeout = options.Timeout);
                    configureTerminator(sp, 'LF');
                    flush(sp, 'input');
                    pause(options.BootDelay);
                    flush(sp, 'input');

                    writeline(sp, 'ID?');
                    reply = strtrim(char(readline(sp)));
                    if startsWith(reply, 'ID EPsychTeensy')
                        wanted = strtrim(options.DeviceSerial);
                        if isempty(wanted) || contains(reply, ['SN=' wanted])
                            port = candidates{i};
                        end
                    end
                catch
                    % A port held by another process, or a device that does not
                    % answer, is simply not our board.
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

    end  % Static methods


    methods (Static, Access = private)

        function v = optField_(opts, name, default)
            % v = optField_(opts, name, default)
            % Read opts.(name) when present and non-empty, else return default.
            % Lets getCreationSpec's factory tolerate an options struct saved
            % before a newer option existed.
            if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
                v = opts.(name);
            else
                v = default;
            end
        end

        function [state, ok] = toDeviceState_(raw)
            % [state, ok] = toDeviceState_(raw)
            % Convert a wire value to hw.DeviceState without throwing.
            %
            % ok is false for anything the enumeration does not define, which
            % lets callers keep their cached state instead of adopting a
            % garbled reply. That matters because RunExpt reads Idle as
            % "stop the session".
            state = hw.DeviceState.Idle;
            ok = false;

            value = str2double(raw);
            if isnan(value) || value ~= floor(value)
                return
            end
            if ~ismember(value, double(enumeration('hw.DeviceState')))
                return
            end

            state = hw.DeviceState(value);
            ok = true;
        end

    end  % private static methods


    methods (Access = protected)

        % --- Byte-level transport seam ------------------------------------
        % These wrap the serialport object so a test subclass can simulate the
        % firmware with no board and no hardware support package
        % (see tmp/Teensy_Mock).

        function openPort_(obj)
            % openPort_(obj)
            % Open the serial port and configure the line terminator.
            obj.HW = serialport(obj.Port, obj.BaudRate, Timeout = obj.Timeout);
            configureTerminator(obj.HW, 'LF');
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
            % Write one LF-terminated command line.
            writeline(obj.HW, s);
        end

        function n = bytesAvailable_(obj)
            % n = bytesAvailable_(obj)
            n = obj.HW.NumBytesAvailable;
        end

        function s = readLine_(obj)
            % s = readLine_(obj)
            % Read one line, trimmed. Returns '' on timeout rather than throwing.
            try
                s = strtrim(char(readline(obj.HW)));
            catch
                s = '';
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


    methods (Access = protected)

        function close_interface(obj)
            % close_interface(obj)
            % Return the board to Idle and release the serial port.
            if obj.IsConnected
                try
                    obj.pendingWrites_ = {};
                    obj.transact_(sprintf('MODE %d', int8(hw.DeviceState.Idle)));
                catch ME
                    vprintf(0, 1, ME);
                end
            end
            obj.linkReady_ = false;
            obj.closePort_();
            obj.snapshot_ = struct();
            obj.snapshotTic_ = [];
            obj.pendingWrites_ = {};
        end

    end  % protected methods


    methods (Access = private)

        % --- Transactions --------------------------------------------------

        function reply = transact_(obj, cmd)
            % reply = transact_(obj, cmd)
            % Send one command and read its single reply line.
            %
            % Returns '' on timeout. Following house style, a timeout warns
            % through vprintf and degrades rather than throwing, so a flaky USB
            % link does not abort a session mid-trial.
            reply = '';
            if ~obj.IsConnected
                return
            end

            try
                obj.writeLine_(cmd);
                reply = obj.readLine_();
            catch ME
                vprintf(0, 1, 'Teensy: transport error on "%s": %s', cmd, ME.message);
                return
            end

            if isempty(reply)
                vprintf(0, 1, 'Teensy: timed out waiting for a reply to "%s"', cmd);
            elseif startsWith(reply, 'ERR')
                vprintf(0, 1, 'Teensy: "%s" -> %s', cmd, reply);
            end
        end

        function lines = transactBlock_(obj, cmd, blockName)
            % lines = transactBlock_(obj, cmd, blockName)
            % Send a command that answers with a "<NAME> BEGIN ... <NAME> END"
            % block and return the lines between the markers.
            lines = {};
            if ~obj.IsConnected
                return
            end

            try
                obj.writeLine_(cmd);
            catch ME
                vprintf(0, 1, 'Teensy: transport error on "%s": %s', cmd, ME.message);
                return
            end

            header = obj.readLine_();
            if ~strcmp(header, [blockName ' BEGIN'])
                if startsWith(header, 'ERR')
                    vprintf(0, 1, 'Teensy: "%s" -> %s', cmd, header);
                else
                    vprintf(0, 1, 'Teensy: expected "%s BEGIN" from "%s", got "%s"', ...
                        blockName, cmd, header);
                end
                return
            end

            terminator = [blockName ' END'];
            deadline = tic;
            while toc(deadline) < obj.Timeout * 10
                ln = obj.readLine_();
                if isempty(ln)
                    vprintf(0, 1, 'Teensy: "%s" block was not terminated', cmd);
                    return
                end
                if strcmp(ln, terminator)
                    return
                end
                lines{end + 1} = ln;
            end
            vprintf(0, 1, 'Teensy: "%s" block exceeded its deadline', cmd);
        end

        function sendSetM_(obj, chunk)
            % sendSetM_(obj, chunk)
            % Send one assembled SETM line and report a rejection.
            reply = obj.transact_(chunk);
            if ~startsWith(reply, 'OK')
                vprintf(0, 1, 'Teensy: batched write failed: %s -> %s', chunk, reply);
            end
        end

        function queueWrite_(obj, wire, valStr)
            % queueWrite_(obj, wire, valStr)
            % Buffer a write, replacing any earlier pending write to the same
            % parameter so only the final value is sent.
            if ~isempty(obj.pendingWrites_)
                existing = find(strcmp(obj.pendingWrites_(:, 1), wire), 1);
                if ~isempty(existing)
                    obj.pendingWrites_{existing, 2} = valStr;
                    return
                end
            end
            obj.pendingWrites_(end + 1, :) = {wire, valStr};
        end

        % --- Reads ---------------------------------------------------------

        function refreshSnapshot_(obj)
            % refreshSnapshot_(obj)
            % Refresh the batched read cache if it is older than SnapshotInterval.
            %
            % One SNAP carries every readable value plus the mode, which is what
            % keeps the runtime's per-trial sweep over all readable parameters to
            % a single round-trip.
            if ~isempty(obj.snapshotTic_) && toc(obj.snapshotTic_) < obj.SnapshotInterval
                return
            end

            reply = obj.transact_('SNAP');
            if ~startsWith(reply, 'SNAP')
                return
            end

            tok = strsplit(strtrim(reply));
            snap = struct();
            for i = 2:numel(tok)
                kv = strsplit(tok{i}, '=');
                if numel(kv) ~= 2
                    continue
                end
                key = kv{1};
                switch key
                    case 'MODE'
                        [m, ok] = hw.Teensy.toDeviceState_(kv{2});
                        if ok
                            obj.modeCache_ = m;
                            obj.modeCacheTic_ = tic;
                        end
                    case {'NEVT', 'US'}
                        % Housekeeping fields, not parameters.
                    otherwise
                        snap.(matlab.lang.makeValidName(key)) = obj.parseValue_(kv{2});
                end
            end

            obj.snapshot_ = snap;
            obj.snapshotTic_ = tic;
        end

        function v = readOne_(obj, wire)
            % v = readOne_(obj, wire)
            % Direct single-parameter read for values SNAP does not carry.
            v = [];
            reply = obj.transact_(sprintf('GET %s', wire));
            tok = strsplit(strtrim(reply));
            if numel(tok) >= 3 && strcmp(tok{1}, 'VAL')
                v = obj.parseValue_(strjoin(tok(3:end), ' '));
            end
        end

        function m = queryMode_(obj)
            % m = queryMode_(obj)
            % Live mode query. On any failure the cache is returned unchanged.
            %
            % Never synthesize Idle here: RunExpt treats Idle as "stop the
            % session", so a garbled reply must not end the experiment.
            m = obj.modeCache_;
            reply = obj.transact_('MODE?');
            tok = strsplit(strtrim(reply));
            if numel(tok) >= 2 && strcmp(tok{1}, 'MODE')
                [parsed, ok] = hw.Teensy.toDeviceState_(tok{2});
                if ok
                    m = parsed;
                    obj.modeCache_ = m;
                end
            end
            obj.modeCacheTic_ = tic;
        end

        % --- Value marshalling ---------------------------------------------

        function wire = wireName_(~, P)
            % wire = wireName_(~, P)
            % Backend name for a parameter, falling back to its display name.
            wire = hw.Interface.getHardwareParameterName(P);
            if isempty(wire)
                wire = P.Name;
            end
            wire = char(wire);
        end

        function s = formatValue_(~, P, value)
            % s = formatValue_(obj, P, value)
            % Render a parameter value for the wire.
            %
            % Returns '' (and warns) when the value cannot be expressed, because
            % the space-delimited SETM grammar has no escaping.
            s = '';

            if iscell(value)
                if isempty(value)
                    return
                end
                value = value{1};
            end

            if ischar(value) || isstring(value)
                txt = char(string(value));
                if any(isspace(txt))
                    vprintf(0, 1, ['Teensy: value for "%s" contains spaces, which the ' ...
                        'firmware command grammar cannot express. Write skipped.'], P.Name);
                    return
                end
                s = txt;
                return
            end

            if islogical(value)
                value = double(value);
            end

            if ~isnumeric(value) || isempty(value)
                vprintf(0, 1, 'Teensy: unsupported value type "%s" for "%s"', class(value), P.Name);
                return
            end

            switch P.Type
                case {'Integer', 'Boolean'}
                    parts = arrayfun(@(v) sprintf('%d', round(double(v))), value(:)', UniformOutput = false);
                otherwise
                    parts = arrayfun(@(v) sprintf('%.6g', double(v)), value(:)', UniformOutput = false);
            end
            s = strjoin(parts, ',');
        end

        function v = parseValue_(~, txt)
            % v = parseValue_(~, txt)
            % Parse a wire value into a MATLAB value.
            %
            % Comma-separated text becomes a numeric row vector; anything that
            % is not fully numeric is returned as a char array.
            txt = strtrim(char(txt));
            if isempty(txt)
                v = [];
                return
            end

            parts = strsplit(txt, ',');
            nums = str2double(parts);
            if any(isnan(nums)) && ~all(strcmpi(parts, 'nan'))
                v = txt;
            else
                v = nums;
            end
        end

        function channels = channelMap_(obj)
            % channels = channelMap_(obj)
            % Wire names of every parameter, in order.
            %
            % An event row carries the index into this list rather than a name,
            % so a saved event log stays compact and still interpretable.
            channels = {};
            P = obj.all_parameters(includeInvisible = true);
            if isempty(P)
                return
            end
            channels = arrayfun(@(p) obj.wireName_(p), P, UniformOutput = false);
        end

    end  % private methods

end
