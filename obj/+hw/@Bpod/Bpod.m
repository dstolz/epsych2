classdef Bpod < hw.Interface

    % obj = hw.Bpod(port, Name=Value)
    % Hardware interface for a Bpod 0.5/0.6 behavioral state machine.
    %
    % Speaks the Arduino Due firmware's byte protocol directly over a MATLAB
    % serialport handle. The Bpod MATLAB layer at c:\src\Bpod is never loaded:
    % it requires a `global BpodSystem`, opens a splash screen and an 800x400
    % console figure, and its RunStateMatrix blocks in a `while` loop until the
    % trial ends. None of that survives inside a 10 ms timer callback.
    %
    % Firmware protocol notes (these shape the implementation):
    %   - After 'R' the device is a PUSH STREAM. It emits framed messages
    %     [1 nEvents ev...] unsolicited from its 100 us timer ISR. MATLAB is
    %     never required to block; RunStateMatrix's busy-wait is a consumer
    %     convention, not a hardware requirement. pump() replaces it.
    %   - Matrix end is the framed sentinel [1 1 255], followed by a fixed
    %     10-byte epilogue header (uint32 trialStartMs, uint32 matrixStartUs,
    %     uint16 nEvents) and then uint32 x nEvents timestamps.
    %   - 'I' (read input line) answers with a BARE, UNFRAMED byte from the
    %     same ISR that streams framed messages. Issuing 'I' mid-trial
    %     desynchronizes the whole event stream, and the protocol has no CRC,
    %     sequence number, or resync marker. readInput_ is interlocked against
    %     this; do not remove the interlock.
    %   - The firmware resets valves/PWM/BNC/wire ONLY on a clean matrix end or
    %     on 'X'. A MATLAB error mid-trial leaves outputs energized, so
    %     close_interface and delete both force outputs low. See the animal
    %     welfare note in documentation/hw/hw_Bpod.md.
    %   - The device silently stops recording timestamps past 10000 events
    %     while the state machine keeps running, so event and timestamp counts
    %     can legitimately disagree on long or noisy trials.
    %
    % Parameters
    %   port    - Serial port name, e.g. 'COM3'. Empty with AutoDetect=true
    %             probes available ports with the '6' handshake.
    %
    % Name=Value options
    %   Connect (logical)        - Connect on construction. Default true
    %   AutoDetect (logical)     - Probe ports for a board at connect. Default false
    %   BoxID (double)           - Subject box served; names the x_*_N triggers. Default 1
    %   StateMatrixFcn (char)    - Optional builder `sma = f(iface, P)`. Blank
    %                              runs in immediate I/O mode.
    %   Timeout (double)         - Transaction timeout in seconds. Default 1
    %
    % Properties
    %   Port, Timeout, AutoDetect - Connection settings.
    %   BoxID, StateMatrixFcn     - Trial configuration.
    %   IsConnected               - True when the port is open and handshook.
    %   Module                    - Single hw.Module holding the parameter table.
    %   mode                      - Current hw.DeviceState.
    %   FirmwareBuild             - Build number reported by 'F' at connect.
    %   StateNames                - Manifest-ordered state names of the matrix
    %                               most recently uploaded. Event-stream state
    %                               indices refer to THIS ordering, which is add
    %                               order after sendStateMatrix permutes it, not
    %                               declaration order.
    %
    % Methods
    %   connect, disconnect       - Connection management.
    %   get_parameter, set_parameter, trigger - hw.Interface contract.
    %   pump                      - Public escape hatch for the byte pump.
    %   newStateMatrix, addState, setGlobalTimer, setGlobalCounter, sendStateMatrix
    %                             - State matrix authoring, ported from Bpod.
    %   abortMatrix, sendSoftCode, flushOutputs - Immediate-mode control.
    %   setModules                - Replace the Module array while offline.
    %
    % Usage
    %   iface = hw.Bpod('COM3');
    %   iface = hw.Bpod('', AutoDetect=true, BoxID=1);
    %
    %   % Offline construction for serialization round-trip
    %   iface = hw.Bpod('COM3', Connect=false);
    %
    % See also: documentation/hw/hw_Bpod.md, documentation/hw/hw_Interface.md,
    %           hw.Module, hw.Parameter, hw.Teensy


    properties
        Port (1,:) char = ''              % serial port name, e.g. 'COM3'
        Timeout (1,1) double = 1          % transaction timeout in seconds
        HW = []                           % serialport handle (also required by hw.Parameter)

        AutoDetect (1,1) logical = false  % probe ports with the '6' handshake at connect
        BoxID (1,1) double = 1            % subject box; names the x_*_N triggers
        StateMatrixFcn (1,:) char = ''    % builder `sma = f(iface, P)`; blank = immediate mode

        % Timing knobs (public so tests can shorten them).
        BootDelay (1,1) double = 1.5      % seconds after opening the port; the Due re-enumerates

        % TTL on the cached input reads. Sized well under the runtime's 10 ms
        % tick so a fresh tick always re-polls.
        SnapshotInterval (1,1) double = 0.005

        % Bounded work per pump call. A trial that floods events must not let
        % one timer tick run long enough to starve the rest of the session.
        MaxMessagesPerPump (1,1) double = 64

        % Watchdog on the end-of-trial epilogue. The epilogue is length-
        % prefixed but unframed, so a single lost byte would otherwise leave
        % the parser waiting forever with x_TrialComplete_ stuck at 0 and the
        % session frozen at a trial boundary with no error. On expiry the trial
        % force-completes with Aborted = true.
        EpilogueTimeout (1,1) double = 2

        % Hard ceiling on a single trial. Guards against a matrix that never
        % reaches an exit state (or a lost sentinel byte).
        MaxTrialSeconds (1,1) double = 3600
    end

    properties (SetObservable, AbortSet)
        mode  % Current device state (hw.DeviceState)
    end

    properties (Dependent)
        % True when the port is open and the firmware handshook. Deliberately
        % undecorated: MATLAB rejects size/class validation on a property
        % inherited from an abstract declaration.
        IsConnected
    end

    properties (SetAccess = protected)
        Module                             % hw.Module array
        FirmwareBuild (1,1) double = 0     % build number reported by 'F'
        StateNames (1,:) cell = {}         % manifest-ordered names of the live matrix
    end

    properties (Constant)
        Type = "Bpod"

        BAUD_RATE = 115200      % fixed by the firmware's SerialUSB
        TICK_HZ   = 10000       % firmware Timer3 tick: 100 us
        MAX_STATES = 128        % firmware state table depth
        MAX_TIMESTAMPS = 10000  % firmware stops recording past this, silently

        % The frozen readable trial record. populateModule_ creates exactly
        % these as Visible=true/Access='Read' parameters, pump_ publishes
        % exactly these, and get_parameter serves exactly these. Keeping the
        % three in one list is not tidiness: a name that drifts between them
        % reads NaN forever and still lands in DATA, so the session records a
        % full-looking result set of nothing. Changing this list changes the
        % DATA field set, which must stay fixed for the life of the interface.
        RESULT_PARAMETERS = { ...
            'RespCode','RespLatency','nStatesVisited','LastStateCode', ...
            'LastStateName','TrialStartTimestamp','TrialDuration_Actual', ...
            'Aborted','LastSoftCode','EventCountMismatch', ...
            'StateCodes','StateTimestamps','EventCodes','EventTimestamps'}

        % Canonical Bpod 0.5/0.6 vocabularies, mirrored verbatim from
        % BpodObject.m:84-91 so addState validates without the global.
        EVENT_NAMES = { ...
            'Port1In','Port1Out','Port2In','Port2Out','Port3In','Port3Out','Port4In','Port4Out','Port5In','Port5Out', ...
            'Port6In','Port6Out','Port7In','Port7Out','Port8In','Port8Out','BNC1High','BNC1Low','BNC2High','BNC2Low', ...
            'Wire1High','Wire1Low','Wire2High','Wire2Low','Wire3High','Wire3Low','Wire4High','Wire4Low', ...
            'SoftCode1','SoftCode2','SoftCode3','SoftCode4','SoftCode5','SoftCode6','SoftCode7','SoftCode8','SoftCode9','SoftCode10', ...
            'Unused','Tup','GlobalTimer1_End','GlobalTimer2_End','GlobalTimer3_End','GlobalTimer4_End','GlobalTimer5_End', ...
            'GlobalCounter1_End','GlobalCounter2_End','GlobalCounter3_End','GlobalCounter4_End','GlobalCounter5_End'}

        OUTPUT_ACTION_NAMES = { ...
            'ValveState','BNCState','WireState','Serial1Code','Serial2Code','SoftCode', ...
            'GlobalTimerTrig','GlobalTimerCancel','GlobalCounterReset', ...
            'PWM1','PWM2','PWM3','PWM4','PWM5','PWM6','PWM7','PWM8'}
    end

    properties (Access = protected)
        % Connection state. Reachable by test subclasses (tmp/Bpod_Mock).
        linkReady_ (1,1) logical = false    % port open and handshake accepted
        modeCache_ (1,1) hw.DeviceState = hw.DeviceState.Idle

        % Output shadow. Bpod's own ManualOverride is toggle-only, mutates
        % HardwareState, disables sibling GUI buttons, and reads three of its
        % data bytes out of console edit boxes, so it is never used. Instead we
        % keep an absolute local shadow and always emit a full mask.
        valves_    (1,8) double = zeros(1,8)
        pwm_       (1,8) double = zeros(1,8)
        bncOut_    (1,2) double = zeros(1,2)
        wireOut_   (1,4) double = zeros(1,4)

        % Cached input reads, guarded by SnapshotInterval and by the 'I'
        % interlock (never issue 'I' while a matrix is live).
        inputCache_ = struct()
        inputCacheTic_ = []

        % Byte pump state. The pump is resumable: it parses greedily from the
        % front of rxBuf_ and returns the instant a partial message is at the
        % head, so a message split across ticks decodes identically.
        rxBuf_ (1,:) uint8 = uint8([])
        matrixRunning_ (1,1) logical = false
        awaitingEpilogue_ (1,1) logical = false
        pendingEventCount_ (1,1) double = 0
        epiHdr_ = []
        pumping_ (1,1) logical = false      % re-entrancy guard, released by onCleanup

        % Accumulating trial record, reset at each x_NewTrial_.
        stateCodes_ (1,:) double = []
        stateTimes_ (1,:) double = []
        eventCodes_ (1,:) double = []
        eventTimes_ (1,:) double = []
        lastSoftCode_ (1,1) double = 0
        trialComplete_ (1,1) logical = false
        trialAborted_ (1,1) logical = false
        trialNum_ (1,1) double = 0
        trialTic_ = []
        epilogueTic_ = []

        % Compiled matrix memo. Skipping an unchanged re-upload reduces trial
        % start to a single 'R' byte.
        lastMatrix_ = []
        lastPayload_ (1,:) uint8 = uint8([])
        currentState_ (1,1) double = 0
    end


    methods

        function obj = Bpod(port, options)
            % obj = hw.Bpod(port, Name=Value)
            % Construct a Bpod interface and optionally connect.
            %
            % Parameters
            %   port - Serial port name. Default '' (requires AutoDetect).
            % Name=Value
            %   Connect (logical)      - Connect on construction. Default true
            %   AutoDetect (logical)   - Probe ports for the board. Default false
            %   BoxID (double)         - Subject box served. Default 1
            %   StateMatrixFcn (char)  - Builder `sma = f(iface, P)`. Default ''
            %   Timeout (double)       - Transaction timeout (s). Default 1
            arguments
                port (1,:) char = ''
                options.Connect (1,1) logical = true
                options.AutoDetect (1,1) logical = false
                options.BoxID (1,1) double {mustBeInteger, mustBePositive} = 1
                options.StateMatrixFcn (1,:) char = ''
                options.Timeout (1,1) double = 1
                options.BootDelay (1,1) double = 1.5
            end

            obj.Port = port;
            obj.AutoDetect = options.AutoDetect;
            obj.BoxID = options.BoxID;
            obj.StateMatrixFcn = options.StateMatrixFcn;
            obj.Timeout = options.Timeout;
            obj.BootDelay = options.BootDelay;
            obj.Module = hw.Module.empty(1, 0);

            if options.Connect
                obj.connect();
            end
        end

        function delete(obj)
            % delete(obj)
            % Abort any running matrix, drive outputs low, and release the port.
            %
            % This is the last line of defence for animal welfare: the firmware
            % only resets valves on a clean matrix end, and the framework's own
            % error path cannot be relied upon (RunExpt assigns RUNTIME.ERROR,
            % a property epsych.Runtime never declares).
            obj.close_interface();
        end

        function connect(obj)
            % connect(obj)
            % Open the serial port, handshake, and build the parameter table.
            % Safe to call when already connected.
            if obj.IsConnected
                return
            end
            obj.setup_interface();
        end

        function disconnect(obj)
            % disconnect(obj)
            % Close the serial port. Not on the abstract contract, but both
            % RunExpt.onCloseRequest and epsych.SelfTest.checkHardware call it.
            obj.close_interface();
        end

        function tf = get.IsConnected(obj)
            % tf = get.IsConnected(obj)
            % True when the port handle is live and the firmware handshook.
            %
            % HW normally holds a serialport handle, but a test subclass that
            % overrides the transport seam parks a non-handle sentinel there,
            % so the validity check only applies when there is a handle to
            % check. Removing the isa guard breaks tmp/Bpod_Mock.
            tf = obj.linkReady_ && ~isempty(obj.HW);
            if tf && isa(obj.HW, 'handle')
                tf = isvalid(obj.HW);
            end
        end

        function m = get.mode(obj)
            % m = get.mode(obj)
            % Current device state, served from cache.
            %
            % RunExpt.PsychTimerRunTime reads this on every interface on every
            % 10 ms tick and stops the session when any interface reports Idle,
            % so this must be cheap and must never fabricate Idle. It is also
            % the guaranteed per-tick hook the byte pump hangs off.
            obj.pump();
            m = obj.modeCache_;
        end

        function set.mode(obj, m)
            % set.mode(obj, m)
            % Record the requested device state.
            %
            % Bpod has no device-side run mode: a trial exists only between 'R'
            % and the matrix-end sentinel. Leaving Record/Preview aborts any
            % matrix left running from a previous session.
            m = hw.DeviceState(m);
            if m.isIdle() && obj.linkReady_
                obj.abortMatrix();
            end
            obj.modeCache_ = m;
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
                error('hw:Bpod:ModulesWhileConnected', ...
                    'Disconnect before replacing modules on a live Bpod interface.');
            end
            obj.Module = modules;
        end

        function prepareRecording(obj, runtime)
            % prepareRecording(obj, runtime)
            % Lifecycle hook run immediately before the session enters its mode.
            %
            % Bpod 0.5 has exactly one state machine and one 'R' opcode, and
            % epsych.Protocol.addInterface rejects a second interface of the
            % same Type with only a vprintf and a bare return. A two-subject
            % configuration would therefore have subject 2's dispatchNextTrial
            % clobber subject 1's in-flight matrix with no error at all, so
            % this is a hard failure rather than a warning.
            if ~isempty(runtime) && isprop(runtime, 'NSubjects') && runtime.NSubjects > 1
                error('hw:Bpod:MultipleSubjects', ...
                    ['hw.Bpod serves one box: the device has a single state machine. ' ...
                     'This session has %d subjects, whose trials would overwrite each ' ...
                     'other silently. Run one subject per Bpod.'], runtime.NSubjects);
            end
        end

        function tf = usesStateMatrix(obj)
            % tf = usesStateMatrix(obj)
            % True when a state-matrix builder is configured. Blank runs the
            % interface in immediate I/O mode, where the host times the trial.
            tf = ~isempty(obj.StateMatrixFcn);
        end
    end


    % ---- Contract methods and protected helpers implemented in separate files
    methods
        value  = get_parameter(obj, name, options)
        result = set_parameter(obj, name, value)
        result = trigger(obj, name)
        pump(obj)
        [tf, msg] = readHardwareParameters(obj, module, options)
        results = selfTest(obj, options)
        tf = canReadHardwareParameters(obj, module)

        sma = newStateMatrix(obj)
        sma = addState(obj, varargin)
        sma = setGlobalTimer(obj, sma, timerNumber, timerDuration)
        sma = setGlobalCounter(obj, sma, counterNumber, targetEventName, threshold)
        sendStateMatrix(obj, sma)

        abortMatrix(obj)
        sendSoftCode(obj, code)
        flushOutputs(obj, options)
    end

    methods (Access = protected)
        setup_interface(obj)
        close_interface(obj)
        populateModule_(obj, module, options)
        pump_(obj)

        % The single publisher of the frozen trial-result set. A method rather
        % than a local function in pump_.m because abortMatrix ends trials too,
        % and a second copy of the result vocabulary is what let an aborted
        % trial record the previous trial's results.
        finalizeTrial_(obj, timestamps, hdr)

        % Shared helpers. Declared here because MATLAB requires every method
        % living in its own file to be declared in the classdef; helpers used
        % by only one method file are local functions there instead.
        resetShadow_(obj)
        writeOutputs_(obj, options)   % emit absolute OV/OP/OB/OW masks
        v = readInput_(obj, kind, index)
        s = parameterStruct(obj)
        payload = compileMatrix_(obj)
    end

    % ---- Transport seam.
    % Isolated so tmp/Bpod_Mock can override exactly this surface and leave
    % every line of protocol logic running unchanged.
    methods (Access = protected)
        openPort_(obj)
        closePort_(obj)
        write_(obj, bytes)
        b = readNow_(obj, n)
        b = readExactly_(obj, n, timeout)
        n = bytesAvailable_(obj)
        flushInput_(obj)
    end


    methods (Static)
        spec = getCreationSpec()
        port = findBoardPort(options)

        function v = optField_(opts, name, default)
            % v = hw.Bpod.optField_(opts, name, default)
            % Tolerant reader for a creation-spec option struct.
            v = default;
            if isstruct(opts) && isfield(opts, name) && ~isempty(opts.(name))
                v = opts.(name);
            end
        end
    end
end
