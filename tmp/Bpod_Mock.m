classdef Bpod_Mock < hw.Bpod
% Bpod_Mock - In-process Bpod 0.5/0.6 firmware simulator for hw.Bpod.
%
% Overrides ONLY hw.Bpod's seven byte-level transport-seam methods, so every
% line of protocol logic -- the '6'/'F' handshake, the absolute output shadow,
% the 'I' snapshot cache and its mid-trial interlock, the state-matrix encoder,
% the resumable byte pump, the epilogue decoder and both watchdogs -- runs
% exactly as it would against a real Arduino Due, with no serial port and no
% hardware support package.
%
% Mirrors tmp/Teensy_Mock, which does the same for the EPsychTeensy backend.
%
% THE STAGE/RELEASE SPLIT IS THE POINT. A real Bpod is a push stream after 'R':
% it emits framed [1 nEvents ev...] messages from a 100 us ISR, so a message can
% straddle any number of MATLAB timer ticks. Device output therefore lands in
% two places here:
%   staged_ - produced by the simulated device but NOT yet on the wire
%   out_    - "in the driver's input buffer", visible to bytesAvailable_/readNow_
% stage() adds to the first, release(n) moves n bytes to the second. A test can
% therefore hand the pump a message split at an arbitrary byte boundary and
% assert the decode is identical, which is the property the whole non-blocking
% architecture rests on.
%
% Usage
%   mock = Bpod_Mock();                       % connects immediately
%   mock.RunScript = [Bpod_Mock.eventMessage(0), Bpod_Mock.endSentinel(), ...
%                     Bpod_Mock.epilogueBytes(0, 0, 1000)];
%   mock.trigger('x_NewTrial_1');             % 'R' stages the script
%   mock.release(3); mock.pump();             % hand over one message
%
% Properties
%   Log             - Every command the simulated firmware received, in order,
%                     each a uint8 row including its opcode. This is what most
%                     assertions read.
%   InputRaw        - Raw pin levels answered by 'I', as .P (1x8), .B (1x2),
%                     .W (1x4). RAW, before any polarity mapping: readInput_
%                     owns the mapping and this mock must not pre-apply it.
%   RunScript       - Bytes staged (not released) when the device receives 'R'.
%   AbortBurst      - Bytes released when the device receives 'X'. Empty means
%                     "build the documented burst from AbortTimestamps".
%   AbortTimestamps - Device timestamps, in 100 us ticks, reported in the burst
%                     that 'X' provokes.
%   DeviceOutputs   - Output lines as the simulated hardware holds them, so a
%                     test can assert valves really went low rather than only
%                     that a command was written.
%   TransportCalls  - Count of seam calls. selfTest() must not change it.
%
% See also: hw.Bpod, tmp/smoke_test_bpod.m, tmp/smoke_test_bpod_protocol.m,
%           c:\src\Bpod\Firmware\Bpod_MainModule_0_6\Bpod_MainModule_0_6.ino

    properties
        Log (1,:) cell = {}                 % commands received by the simulated firmware

        % Raw pin levels returned by 'I'. Deliberately raw: the firmware's port
        % lines are INPUT_PULLUP and its BNC sense is build-dependent, and
        % hw.Bpod.readInput_ is the single place those mappings live.
        InputRaw = struct('P', zeros(1, 8), 'B', zeros(1, 2), 'W', zeros(1, 4))

        FirmwareBuildByte (1,1) double = 6   % answer to 'F'
        MatrixAckByte (1,1) double = 1       % answer to a 'P' upload

        RunScript (1,:) uint8 = uint8([])    % staged by 'R'
        AbortBurst (1,:) uint8 = uint8([])   % released by 'X'; empty = build it
        AbortTimestamps (1,:) double = []    % ticks reported in the 'X' burst
    end

    properties (SetAccess = private)
        % What the simulated hardware is actually driving.
        DeviceOutputs = struct('V', 0, 'P', zeros(1, 8), 'B', 0, 'W', 0)

        LastMatrixPayload (1,:) uint8 = uint8([])  % bytes of the most recent 'P'
        RunCount (1,1) double = 0                  % 'R' opcodes received
        AbortCount (1,1) double = 0                % 'X' opcodes received
        SoftCodes (1,:) double = []                % codes delivered by 'V' 'S'
        SerialBytes = zeros(0, 2)                  % [channel byte] from 'H'

        TransportCalls (1,1) double = 0            % seam calls made by hw.Bpod
        ReadTimeouts (1,1) double = 0              % readExactly_ calls that came up short
    end

    properties (Access = private)
        out_ (1,:) uint8 = uint8([])     % released: visible to the host
        staged_ (1,:) uint8 = uint8([])  % produced but not yet on the wire
        cmd_ (1,:) uint8 = uint8([])     % partial host command awaiting its operands
        portOpen_ (1,1) logical = false
        running_ (1,1) logical = false
    end


    methods

        function obj = Bpod_Mock(options)
            % obj = Bpod_Mock(Name=Value)
            % Construct the simulator and connect.
            %
            % Name=Value
            %   BoxID (double)         - Box identifier used in the x_*_<BoxID>
            %                            parameter names. Default 1
            %   Connect (logical)      - Connect on construction. Default true
            %   StateMatrix (logical)  - Configure the bundled state-matrix
            %                            builder, i.e. run in state-matrix mode
            %                            rather than immediate I/O. Default true
            %   Port (char)            - Nominal port name. Default 'MOCK'
            arguments
                options.BoxID (1,1) double = 1
                options.Connect (1,1) logical = true
                options.StateMatrix (1,1) logical = true
                options.Port (1,:) char = 'MOCK'
            end

            if options.StateMatrix
                builder = 'Bpod_Mock.testStateMatrix';
            else
                builder = '';
            end

            % BoxID and the builder must be set before connect: populateModule_
            % names the x_*_<BoxID> parameters from BoxID, and usesStateMatrix()
            % decides which pump path setup leaves behind.
            obj@hw.Bpod(options.Port, Connect = false, BoxID = options.BoxID, ...
                StateMatrixFcn = builder, BootDelay = 0);

            % No wire, so no wire time. Keeps a deliberately-short read (the
            % epilogue drain probing for bytes that will never come) instant.
            obj.Timeout = 0.05;

            if options.Connect
                obj.connect();
            end
        end


        % --- Device-side scripting ------------------------------------------

        function stage(obj, bytes)
            % stage(obj, bytes)
            % Queue bytes as PRODUCED BY THE DEVICE BUT NOT YET ON THE WIRE.
            %
            % Nothing here is visible to bytesAvailable_ or readNow_ until
            % release() hands it over, which is what lets a test split a message
            % at an arbitrary byte boundary.
            obj.staged_ = [obj.staged_, uint8(reshape(bytes, 1, []))];
        end

        function n = release(obj, n)
            % n = release(obj, n)
            % Move up to n staged bytes onto the wire. Default: all of them.
            %
            % Returns the number actually released, so a caller driving a
            % fragment list can tell when the stream has run out.
            arguments
                obj
                n (1,1) double {mustBeNonnegative} = inf
            end
            k = min(floor(n), numel(obj.staged_));
            if k < 1
                n = 0;
                return
            end
            obj.out_ = [obj.out_, obj.staged_(1:k)];
            obj.staged_(1:k) = [];
            n = k;
        end

        function n = stagedCount(obj)
            % n = stagedCount(obj)
            % Bytes the device has produced but not yet put on the wire.
            n = numel(obj.staged_);
        end

        function n = bufferedCount(obj)
            % n = bufferedCount(obj)
            % Bytes on the wire that the host has not read yet.
            n = numel(obj.out_);
        end

        function startTrialDirect(obj, sma)
            % startTrialDirect(obj, sma)
            % Upload `sma` and start the matrix, bypassing trigger('x_NewTrial_').
            %
            % A TEST SCAFFOLD, NOT A SUPPORTED PATH. It exists only so the byte
            % pump can still be exercised while hw.Bpod's own trial-start path
            % is broken: trigger's startTrial_ calls compileMatrix_ on the
            % freshly built matrix, before sendStateMatrix has permuted it and
            % written sma.nStates, so compileMatrix_ raises
            % hw:Bpod:MatrixShapeMismatch on every trial. The smoke test asserts
            % the real path separately and only falls back to this when it
            % throws, so the workaround disappears the moment the defect is
            % fixed.
            %
            % Everything below is startTrial_'s tail, verbatim.
            arguments
                obj
                sma (1,1) struct
            end

            obj.sendStateMatrix(sma);

            obj.trialComplete_ = false;
            obj.trialAborted_ = false;

            obj.write_(uint8('R'));

            obj.matrixRunning_ = true;
            obj.awaitingEpilogue_ = false;
            obj.currentState_ = 1;
            obj.trialTic_ = tic;
            obj.trialNum_ = obj.trialNum_ + 1;
        end

        function setInput(obj, kind, index, raw)
            % setInput(obj, kind, index, raw)
            % Set the RAW level of one input pin, as digitalReadDirect would
            % report it.
            %
            % Parameters:
            %   kind  - 'P' port, 'B' BNC, or 'W' wire.
            %   index - One-based channel number.
            %   raw   - 0 or 1, the raw pin level. No polarity mapping is
            %           applied here; that belongs to hw.Bpod.readInput_.
            arguments
                obj
                kind (1,1) char {mustBeMember(kind, {'P', 'B', 'W'})}
                index (1,1) double {mustBeInteger, mustBePositive}
                raw (1,1) double
            end
            v = obj.InputRaw.(kind);
            v(index) = double(raw ~= 0);
            obj.InputRaw.(kind) = v;
        end


        % --- Inspection -----------------------------------------------------

        function resetLog(obj)
            % resetLog(obj)
            % Clear the command log and the transport-call counter.
            obj.Log = {};
            obj.TransportCalls = 0;
        end

        function ops = logOpcodes(obj, fromIndex)
            % ops = logOpcodes(obj)
            % ops = logOpcodes(obj, fromIndex)
            % Opcode character of each logged command, from fromIndex onward.
            arguments
                obj
                fromIndex (1,1) double = 1
            end
            entries = obj.Log(min(fromIndex, numel(obj.Log) + 1):end);
            ops = cellfun(@(c) char(c(1)), entries, UniformOutput = false);
        end

        function cmds = commandsOfType(obj, opcode, fromIndex)
            % cmds = commandsOfType(obj, opcode)
            % cmds = commandsOfType(obj, opcode, fromIndex)
            % Every logged command whose opcode is `opcode`, from fromIndex on.
            arguments
                obj
                opcode (1,1) char
                fromIndex (1,1) double = 1
            end
            entries = obj.Log(min(fromIndex, numel(obj.Log) + 1):end);
            keep = cellfun(@(c) char(c(1)) == opcode, entries);
            cmds = entries(keep);
        end

        function r = trialRecord(obj)
            % r = trialRecord(obj)
            % Snapshot the protected trial record the byte pump accumulates.
            %
            % A subclass may read its superclass's protected properties, which
            % is the only reason this mock can assert on the decode without
            % going through the parameter table (whose result names are a
            % separate contract, tested separately).
            r = struct( ...
                'stateCodes',       obj.stateCodes_, ...
                'stateTimes',       obj.stateTimes_, ...
                'eventCodes',       obj.eventCodes_, ...
                'eventTimes',       obj.eventTimes_, ...
                'lastSoftCode',     obj.lastSoftCode_, ...
                'currentState',     obj.currentState_, ...
                'trialComplete',    obj.trialComplete_, ...
                'trialAborted',     obj.trialAborted_, ...
                'trialNum',         obj.trialNum_, ...
                'matrixRunning',    obj.matrixRunning_, ...
                'awaitingEpilogue', obj.awaitingEpilogue_, ...
                'rxPending',        numel(obj.rxBuf_), ...
                'results',          obj.inputCache_);
        end

        function s = builderStruct(obj)
            % s = builderStruct(obj)
            % Public view of hw.Bpod.parameterStruct, which is protected.
            %
            % This is the struct a state-matrix builder is handed as its second
            % argument, so a test needs to see it; a subclass may call its
            % superclass's protected methods, a script may not.
            s = obj.parameterStruct();
        end

        function s = shadow(obj)
            % s = shadow(obj)
            % Snapshot the absolute output shadow hw.Bpod maintains.
            s = struct('valves', obj.valves_, 'pwm', obj.pwm_, ...
                'bncOut', obj.bncOut_, 'wireOut', obj.wireOut_);
        end

    end  % public methods


    methods (Access = protected)

        % --- Transport seam overrides ---------------------------------------
        % These seven files are the entire surface hw.Bpod uses to reach a
        % serial port. Nothing else in the class is replaced.

        function openPort_(obj)
            % HW must be a scalar: hw.Parameter declares HW (1,1) and copies it
            % from the parent interface when a parameter is constructed. A plain
            % struct is deliberately NOT a handle, which is the case
            % hw.Bpod.get.IsConnected guards with its isa(obj.HW,'handle') test.
            obj.TransportCalls = obj.TransportCalls + 1;
            obj.HW = struct('Mock', true);
            obj.portOpen_ = true;
            obj.out_ = uint8([]);
            obj.staged_ = uint8([]);
            obj.cmd_ = uint8([]);
        end

        function closePort_(obj)
            obj.TransportCalls = obj.TransportCalls + 1;
            obj.HW = [];
            obj.portOpen_ = false;
            obj.out_ = uint8([]);
            obj.cmd_ = uint8([]);
        end

        function write_(obj, bytes)
            % Mirrors hw.Bpod.write_: normalize, then drop silently when the
            % link is down. Dropping rather than throwing is what makes offline
            % construction and ProtocolDesigner editing benign, so the mock must
            % reproduce it or those paths would pass here and fail on a rig.
            obj.TransportCalls = obj.TransportCalls + 1;

            if isempty(bytes)
                return
            end
            if ischar(bytes) || isstring(bytes)
                data = uint8(char(bytes));
            else
                data = uint8(reshape(double(bytes), 1, []));
            end

            if ~obj.linkReady_ || isempty(obj.HW)
                return
            end

            obj.cmd_ = [obj.cmd_, data];
            obj.processCommands_();
        end

        function b = readNow_(obj, n)
            arguments
                obj
                n (1,1) double {mustBeNonnegative} = inf
            end
            obj.TransportCalls = obj.TransportCalls + 1;
            b = uint8([]);
            if n < 1 || isempty(obj.HW)
                return
            end
            k = min(floor(n), numel(obj.out_));
            if k < 1
                return
            end
            b = obj.out_(1:k);
            obj.out_(1:k) = [];
        end

        function b = readExactly_(obj, n, timeout)
            % Mirrors hw.Bpod.readExactly_'s CONTRACT, not its wall clock:
            % nothing can arrive during a synchronous call into this mock, so
            % waiting out the timeout would only burn CPU. The failure behaviour
            % is reproduced exactly, including discarding the partial reply so a
            % half-arrived answer cannot be mistaken for the front of the next.
            arguments
                obj
                n (1,1) double {mustBeNonnegative, mustBeInteger}
                timeout (1,1) double {mustBeNonnegative} = obj.Timeout
            end
            obj.TransportCalls = obj.TransportCalls + 1;

            b = uint8([]);
            if n < 1 || isempty(obj.HW)
                return
            end

            if numel(obj.out_) < n
                obj.ReadTimeouts = obj.ReadTimeouts + 1;
                vprintf(3, 'Bpod_Mock: %d of %d byte(s) available within %g s; discarding', ...
                    numel(obj.out_), n, timeout);
                obj.out_ = uint8([]);
                return
            end

            b = obj.out_(1:n);
            obj.out_(1:n) = [];
        end

        function n = bytesAvailable_(obj)
            obj.TransportCalls = obj.TransportCalls + 1;
            if isempty(obj.HW)
                n = 0;
                return
            end
            n = numel(obj.out_);
        end

        function flushInput_(obj)
            % Discards the driver buffer only. Staged bytes are still inside the
            % simulated device and have not been sent, exactly as a real board's
            % unsent output survives a host-side flush.
            obj.TransportCalls = obj.TransportCalls + 1;
            obj.out_ = uint8([]);
        end

    end  % protected transport seam


    methods (Access = private)

        function processCommands_(obj)
            % processCommands_(obj)
            % Consume complete host commands from the front of cmd_.
            %
            % Parses by opcode and operand count rather than assuming one
            % write_ call carries one whole command, so a backend that split a
            % command across writes would still be decoded correctly here (and a
            % backend that emitted a stray byte would show up as an unknown
            % opcode rather than silently shifting every later operand).
            while ~isempty(obj.cmd_)
                have = numel(obj.cmd_);
                op = char(obj.cmd_(1));

                switch op
                    case {'6', 'F', 'Z', 'R', 'X'}
                        need = 1;

                    case {'I', 'H', 'V', 'S'}
                        need = 3;

                    case 'O'
                        if have < 2
                            return
                        end
                        if obj.cmd_(2) == uint8('P')
                            need = 10;   % 'O' 'P' + eight PWM duty bytes
                        else
                            need = 3;    % 'O' <V|B|W|S|T> + one byte
                        end

                    case 'P'
                        if have < 2
                            return
                        end
                        nStates = double(obj.cmd_(2));
                        need = 1 + Bpod_Mock.matrixPayloadLength_(nStates);

                    otherwise
                        vprintf(2, 'Bpod_Mock: discarding unknown opcode %d', double(obj.cmd_(1)));
                        obj.cmd_(1) = [];
                        continue
                end

                if have < need
                    return   % operands still arriving
                end

                c = obj.cmd_(1:need);
                obj.cmd_(1:need) = [];
                obj.Log{end + 1} = c;
                obj.handleCommand_(c);
            end
        end

        function handleCommand_(obj, c)
            % handleCommand_(obj, c)
            % Act on one complete command, exactly as Bpod_MainModule_0_6.ino
            % does, including which commands answer and which are silent.
            switch char(c(1))
                case '6'
                    % Firmware writes 53, then blocks 100 ms in the handler.
                    obj.emit_(uint8(53));

                case 'F'
                    obj.emit_(uint8(obj.FirmwareBuildByte));

                case 'Z'
                    % ConnectedToClient cleared; replies with the CHARACTER '1'.
                    obj.emit_(uint8('1'));

                case 'I'
                    % ONE BARE, UNFRAMED BYTE. Issued while a matrix is running
                    % this is what desynchronizes the whole event stream, which
                    % is why readInput_'s interlock exists.
                    obj.emit_(uint8(obj.inputByte_(char(c(2)), double(c(3)))));

                case 'O'
                    obj.applyOverride_(c);

                case 'H'
                    obj.SerialBytes(end + 1, :) = [double(c(2)), double(c(3))];

                case 'V'
                    if char(c(2)) == 'S'
                        obj.SoftCodes(end + 1) = double(c(3));
                    end

                case 'S'
                    % Soft code by the other opcode; consumes two bytes, silent.

                case 'P'
                    obj.LastMatrixPayload = c(2:end);
                    obj.emit_(uint8(obj.MatrixAckByte));

                case 'R'
                    obj.RunCount = obj.RunCount + 1;
                    obj.running_ = true;
                    if ~isempty(obj.RunScript)
                        obj.staged_ = [obj.staged_, obj.RunScript];
                        obj.RunScript = uint8([]);
                    end

                case 'X'
                    obj.AbortCount = obj.AbortCount + 1;
                    obj.running_ = false;

                    % The device stops streaming events immediately, so anything
                    % still queued inside it is never sent.
                    obj.staged_ = uint8([]);

                    % `if (MatrixFinished)` sits OUTSIDE `if (RunningStateMatrix)`
                    % in the firmware, so 'X' still zeroes every output group and
                    % still emits the full sentinel + header + timestamp burst.
                    obj.zeroOutputs_();
                    burst = obj.AbortBurst;
                    if isempty(burst)
                        burst = [Bpod_Mock.endSentinel(), ...
                            Bpod_Mock.epilogueBytes(0, 0, obj.AbortTimestamps)];
                    else
                        obj.AbortBurst = uint8([]);
                    end
                    obj.emit_(burst);
            end
        end

        function emit_(obj, bytes)
            % emit_(obj, bytes)
            % Put bytes straight on the wire.
            %
            % Command REPLIES are never staged: the host issues them
            % synchronously and blocks in readExactly_, so a staged reply would
            % read as a dead board rather than as a slow one.
            obj.out_ = [obj.out_, uint8(reshape(bytes, 1, []))];
        end

        function b = inputByte_(obj, kind, zeroBasedChannel)
            % b = inputByte_(obj, kind, zeroBasedChannel)
            % Raw pin level answered by 'I'. Channel arrives ZERO-BASED.
            idx = zeroBasedChannel + 1;
            switch kind
                case 'P'
                    v = obj.InputRaw.P;
                case 'B'
                    v = obj.InputRaw.B;
                case 'W'
                    v = obj.InputRaw.W;
                otherwise
                    v = 0;
            end
            if idx >= 1 && idx <= numel(v)
                b = double(v(idx) ~= 0);
            else
                b = 0;
            end
        end

        function applyOverride_(obj, c)
            % applyOverride_(obj, c)
            % Apply an 'O' override to the simulated output hardware.
            switch char(c(2))
                case 'V'
                    obj.DeviceOutputs.V = double(c(3));
                case 'B'
                    obj.DeviceOutputs.B = double(c(3));
                case 'W'
                    obj.DeviceOutputs.W = double(c(3));
                case 'P'
                    obj.DeviceOutputs.P = double(c(3:10));
                otherwise
                    % 'S' and 'T' forward one byte to a hardware serial channel.
                    obj.SerialBytes(end + 1, :) = ...
                        [double(char(c(2)) == 'T') + 1, double(c(3))];
            end
        end

        function zeroOutputs_(obj)
            % zeroOutputs_(obj)
            % Reset the simulated output lines, as the firmware's MatrixFinished
            % block does on a clean matrix end and on 'X'.
            obj.DeviceOutputs = struct('V', 0, 'P', zeros(1, 8), 'B', 0, 'W', 0);
        end

    end  % private methods


    methods (Static, Access = private)

        function n = matrixPayloadLength_(nStates)
            % n = Bpod_Mock.matrixPayloadLength_(nStates)
            % Bytes the firmware reads after the 'P' opcode for nStates states.
            %
            % The firmware performs NO validation and blocks until this exact
            % count arrives, so an encoder that produced a different length
            % would wedge a real board rather than fail loudly. Kept independent
            % of hw.Bpod.compileMatrix_'s own arithmetic on purpose: two
            % independent statements of the same figure is the only check
            % available without a rig.
            n = 1 + nStates * (40 + 17 + 5 + 5) + 5 + 8 + 4 + 4 * (nStates + 10);
        end

    end  % private static methods


    methods (Static)

        function b = eventMessage(zeroBasedCodes)
            % b = Bpod_Mock.eventMessage(zeroBasedCodes)
            % One framed event message: [1 nEvents ev...].
            %
            % Codes are ZERO-BASED firmware codes (Port1In is 0, Tup is 39), the
            % same convention the device puts on the wire.
            zeroBasedCodes = reshape(double(zeroBasedCodes), 1, []);
            b = uint8([1, numel(zeroBasedCodes), zeroBasedCodes]);
        end

        function b = softCodeMessage(code)
            % b = Bpod_Mock.softCodeMessage(code)
            % One [2 softCode] message.
            b = uint8([2, double(code)]);
        end

        function b = endSentinel()
            % b = Bpod_Mock.endSentinel()
            % The framed matrix-end sentinel [1 1 255].
            b = uint8([1, 1, 255]);
        end

        function b = epilogueBytes(trialStartMs, matrixStartUs, ticks)
            % b = Bpod_Mock.epilogueBytes(trialStartMs, matrixStartUs, ticks)
            % The 10-byte epilogue header followed by one uint32 per timestamp.
            %
            % Layout, little-endian and UNFRAMED -- there is no sentinel to
            % resync on, which is why hw.Bpod's epilogue watchdog is mandatory:
            %   uint32 trialStartMs, uint32 matrixStartUs, uint16 nTimestamps
            %
            % Does NOT include the [1 1 255] sentinel; concatenate endSentinel()
            % ahead of it to build a complete end-of-trial burst.
            ticks = reshape(double(ticks), 1, []);
            hdr = [typecast(uint32(trialStartMs), 'uint8'), ...
                   typecast(uint32(matrixStartUs), 'uint8'), ...
                   typecast(uint16(numel(ticks)), 'uint8')];
            b = [uint8(hdr), typecast(uint32(ticks), 'uint8')];
        end

        function sma = testStateMatrix(iface, P)
            % sma = Bpod_Mock.testStateMatrix(iface, P)
            % Two-state matrix used as hw.Bpod's StateMatrixFcn in the tests.
            %
            % Referenced by NAME ('Bpod_Mock.testStateMatrix'), which is how
            % hw.Bpod resolves a builder; str2func handles the dotted static
            % form. The signature is the contract hw.Bpod's buildMatrix_ calls:
            % sma = f(iface, parameterStruct).
            %
            %   1 WaitForPoke  Port1In -> Reward, Tup -> exit, PWM1 on
            %   2 Reward       Tup -> exit, valve 1 open
            %
            % Add order is manifest order, so the event stream's state indices
            % are 1 = WaitForPoke, 2 = Reward.
            %
            % The state timer is NOT taken from P.TrialDuration. hw.Bpod
            % publishes both a writable 'TrialDuration' configuration parameter
            % and a read path that answers the same name with the trial's
            % elapsed time, so P.TrialDuration is NaN before a trial starts and
            % assigning it would build an invalid matrix.
            waitSeconds = 10;
            if isstruct(P) && isfield(P, 'WaitDuration') && ~isempty(P.WaitDuration) ...
                    && isnumeric(P.WaitDuration) && isfinite(P.WaitDuration(1))
                waitSeconds = double(P.WaitDuration(1));
            end

            sma = iface.newStateMatrix();
            sma = iface.addState(sma, ...
                'Name', 'WaitForPoke', ...
                'Timer', waitSeconds, ...
                'StateChangeConditions', {'Port1In', 'Reward', 'Tup', 'exit'}, ...
                'OutputActions', {'PWM1', 255});
            sma = iface.addState(sma, ...
                'Name', 'Reward', ...
                'Timer', 0.1, ...
                'StateChangeConditions', {'Tup', 'exit'}, ...
                'OutputActions', {'Valve', 1});
        end

        function r = runtimeStub(nSubjects)
            % r = Bpod_Mock.runtimeStub(nSubjects)
            % Minimal stand-in for epsych.Runtime carrying only NSubjects.
            %
            % hw.Bpod.prepareRecording guards with isprop(runtime,'NSubjects'),
            % and isprop is false for a struct field, so a struct would silently
            % skip the check being tested. epsych.Runtime cannot be used either:
            % NSubjects is SetAccess=private and is written from the TRIALS
            % setter, which resolves core triggers and dispatches a trial. A
            % dynamicprops object is the cheapest thing that answers isprop.
            %
            % Delete the result when done.
            r = matlab.graphics.GraphicsPlaceholder;
            try
                addprop(r, 'NSubjects');
            catch
                r = figure(Visible = 'off', IntegerHandle = 'off', ...
                    HandleVisibility = 'off');
                addprop(r, 'NSubjects');
            end
            r.NSubjects = nSubjects;
        end

    end  % static methods

end
