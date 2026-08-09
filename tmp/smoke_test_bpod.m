% smoke_test_bpod.m
% Offline smoke tests for hw.Bpod — no hardware required, and c:\src\Bpod is
% never added to the MATLAB path.
%
% Drives the backend against tmp/Bpod_Mock, which simulates the
% Bpod_MainModule_0_6 firmware in process. Because the mock overrides only the
% seven byte-level transport-seam methods, every protocol path exercised here is
% the same code a real board runs: the handshake, the absolute output shadow,
% the 'I' snapshot cache and its mid-trial interlock, the state-matrix encoder,
% the resumable byte pump and the epilogue decoder.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_bpod.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('hw.Bpod', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== hw.Bpod Smoke Test ===\n\n');
results = {};
skips = {};

%% 1. Offline construction
try
    iface = hw.Bpod('COM3', Connect = false);
    results(end+1,:) = check('Offline construction',        true);
    results(end+1,:) = check('Type == "Bpod"',              iface.Type == "Bpod");
    results(end+1,:) = check('IsConnected == false',        ~iface.IsConnected);
    results(end+1,:) = check('Port preserved',              strcmp(iface.Port, 'COM3'));
    results(end+1,:) = check('Module is empty',             isempty(iface.Module));
    % get.mode drives the byte pump; offline it must be inert, not a device query.
    results(end+1,:) = check('mode does not query offline', iface.mode == hw.DeviceState.Idle);

    m = hw.Module(iface, 'Bpod', 'Bpod', uint8(1));
    m.add_parameter('Valve1', false, Type = 'Boolean', Access = 'Any', Visible = false);
    iface.setModules(m);
    results(end+1,:) = check('setModules while offline', numel(iface.Module) == 1);
    results(end+1,:) = check('set_parameter offline returns true', ...
        iface.set_parameter('Valve1', true));

    % The runtime writes through hw.Parameter.set.Value, which stores the value
    % locally and then calls set_parameter. Offline reads have to be driven the
    % same way, because add_parameter seeds Values (design-time levels), not Value.
    P = iface.find_parameter('Valve1', includeInvisible = true);
    P.Value = 1;
    results(end+1,:) = check('get_parameter offline serves the local cache', ...
        isequal(iface.get_parameter('Valve1', includeInvisible = true), 1));
    results(end+1,:) = check('trigger offline returns a double', ...
        isa(iface.trigger('Valve1'), 'double'));
    % Offline writes must not have touched the shadow-to-wire path.
    results(end+1,:) = check('Offline interface is still disconnected', ~iface.IsConnected);
catch ME
    results(end+1,:) = check(['Offline construction: ' ME.message], false);
end

%% 2. getCreationSpec
try
    spec = hw.Bpod.getCreationSpec();
    optNames = {spec.options.name};
    results(end+1,:) = check('getCreationSpec returns hw.InterfaceSpec', isa(spec, 'hw.InterfaceSpec'));
    % getInterfaceEditState looks the spec up by the interface's Type and errors
    % outright when the lookup fails, so this must match char(hw.Bpod.Type).
    results(end+1,:) = check('spec.type == char(hw.Bpod.Type)', ...
        strcmp(char(spec.type), char(hw.Bpod.Type)));
    results(end+1,:) = check('spec has exactly four options', numel(spec.options) == 4);
    results(end+1,:) = check('spec has port option',           any(strcmp(optNames, 'port')));
    results(end+1,:) = check('spec has autoDetect option',     any(strcmp(optNames, 'autoDetect')));
    results(end+1,:) = check('spec has boxID option',          any(strcmp(optNames, 'boxID')));
    results(end+1,:) = check('spec has stateMatrixFcn option', any(strcmp(optNames, 'stateMatrixFcn')));

    results(end+1,:) = check('port renders as text', ...
        strcmp(controlTypeOf(spec, 'port'), 'text'));
    results(end+1,:) = check('autoDetect renders as checkbox', ...
        strcmp(controlTypeOf(spec, 'autoDetect'), 'checkbox'));
    results(end+1,:) = check('boxID renders as numeric', ...
        strcmp(controlTypeOf(spec, 'boxID'), 'numeric'));
    results(end+1,:) = check('stateMatrixFcn renders as text', ...
        strcmp(controlTypeOf(spec, 'stateMatrixFcn'), 'text'));
    results(end+1,:) = check('spec.createFcn is callable', isa(spec.createFcn, 'function_handle'));
    % There must be no Baud Rate option: the main module's SerialUSB is fixed at
    % 115200, and an editable baud would also wake Protocol.toStruct's
    % isprop(iface,'BaudRate') branch on every save.
    results(end+1,:) = check('spec exposes no baudRate option', ~any(strcmp(optNames, 'baudRate')));

    % spec.createFcn is deliberately NOT invoked here. Like hw.Teensy's, it omits
    % Connect=false, so calling it would open a real serial port (or, with an
    % empty port, sweep every port on this machine). The designer supplies its
    % own no-connect factory; smoke_test_bpod_protocol asserts that.
    skips(end+1,:) = skipped('spec.createFcn round trip', ...
        ['calling it would touch real hardware: the factory omits Connect=false, ' ...
         'exactly as hw.Teensy.getCreationSpec does. The designer registry wraps it ' ...
         'with its own Connect=false factory, which smoke_test_bpod_protocol checks ' ...
         'against the registry source.']);
catch ME
    results(end+1,:) = check(['getCreationSpec: ' ME.message], false);
end

%% 3. Connect handshake
% Typed empty, not []: assigning a field to [] would silently turn `mock` into a
% struct and every later section would fail with a confusing message.
mock = hw.Bpod.empty;
try
    mock = Bpod_Mock();
    results(end+1,:) = check('Mock connects', mock.IsConnected);

    % The exact opening byte sequence. '6' must come first and must be answered
    % with byte 53; 'F' reports the firmware build.
    results(end+1,:) = check('First command is the ''6'' handshake', ...
        ~isempty(mock.Log) && isequal(mock.Log{1}, uint8('6')));
    results(end+1,:) = check('Second command is the ''F'' build query', ...
        numel(mock.Log) >= 2 && isequal(mock.Log{2}, uint8('F')));
    results(end+1,:) = check('FirmwareBuild == 6', mock.FirmwareBuild == 6);

    % Connect must leave the hardware in a state the shadow can vouch for.
    results(end+1,:) = check('Connect forces every output group low', ...
        mock.DeviceOutputs.V == 0 && mock.DeviceOutputs.B == 0 && ...
        mock.DeviceOutputs.W == 0 && all(mock.DeviceOutputs.P == 0));
    results(end+1,:) = check('One module was created', numel(mock.Module) == 1);
    results(end+1,:) = check('Module Fs is the firmware tick rate', ...
        mock.Module(1).Fs == hw.Bpod.TICK_HZ);
    results(end+1,:) = check('Handshake left nothing unread', mock.bufferedCount() == 0);
catch ME
    results(end+1,:) = check(['Connect handshake: ' ME.message], false);
end

%% 4. Absolute output semantics
% The assertion that proves hw.Bpod did NOT reproduce Bpod's ManualOverride,
% which is toggle-based: sending it "valve 3" while valve 1 is open opens 3 and
% leaves 1 open only by accident of a shadow kept in a console GUI.
try
    mock.resetLog();
    mock.set_parameter('Valve1', 1);
    ov = mock.commandsOfType('O');
    results(end+1,:) = check('Valve1=1 emits exactly one override', numel(ov) == 1);
    results(end+1,:) = check('Valve1=1 emits [''OV'' 1]', ...
        ~isempty(ov) && isequal(ov{1}, uint8([double('OV'), 1])));

    mock.resetLog();
    mock.set_parameter('Valve3', 1);
    ov = mock.commandsOfType('O');
    results(end+1,:) = check('Valve3=1 emits [''OV'' 5] (absolute, not toggled)', ...
        ~isempty(ov) && isequal(ov{1}, uint8([double('OV'), 5])));

    mock.resetLog();
    mock.set_parameter('Valve1', 0);
    ov = mock.commandsOfType('O');
    results(end+1,:) = check('Valve1=0 emits [''OV'' 4] (full mask re-sent)', ...
        ~isempty(ov) && isequal(ov{1}, uint8([double('OV'), 4])));

    mock.resetLog();
    mock.set_parameter('PWM2', 128);
    ov = mock.commandsOfType('O');
    results(end+1,:) = check('PWM2=128 emits [''OP'' 0 128 0 0 0 0 0 0]', ...
        ~isempty(ov) && isequal(ov{1}, uint8([double('OP'), 0, 128, 0, 0, 0, 0, 0, 0])));
    results(end+1,:) = check('A PWM write does not re-emit the valve mask', numel(ov) == 1);

    results(end+1,:) = check('Device holds the absolute valve mask', mock.DeviceOutputs.V == 4);
    results(end+1,:) = check('Device holds the absolute PWM bytes', ...
        isequal(mock.DeviceOutputs.P, [0 128 0 0 0 0 0 0]));

    % Unchanged groups are not re-sent, but flushOutputs(Force=true) re-asserts
    % everything: that is the post-trial resync the firmware's own output reset
    % makes necessary.
    mock.resetLog();
    mock.set_parameter('PWM2', 128);
    results(end+1,:) = check('Re-writing an unchanged value sends nothing', ...
        isempty(mock.commandsOfType('O')));
    mock.resetLog();
    mock.flushOutputs();
    results(end+1,:) = check('flushOutputs(Force) re-sends all four groups', ...
        numel(mock.commandsOfType('O')) == 4);

    % Leave the box dark for the sections that follow.
    mock.set_parameter('Valve3', 0);
    mock.set_parameter('PWM2', 0);
catch ME
    results(end+1,:) = check(['Absolute output semantics: ' ME.message], false);
end

%% 5. Input reads: encoding, polarity and the snapshot cache
try
    % Raised well above the production 5 ms TTL: three MATLAB-side calls can
    % easily take longer than that, which would expire the cache for reasons
    % that say nothing about the code.
    mock.SnapshotInterval = 5;
    mock.setInput('P', 1, 0);
    mock.resetLog();

    v0 = mock.get_parameter('Port1In', includeInvisible = true);
    icmd = mock.commandsOfType('I');
    results(end+1,:) = check('Reading Port1In issues one ''I''', numel(icmd) == 1);
    results(end+1,:) = check('''I'' sends the channel ZERO-based', ...
        ~isempty(icmd) && isequal(icmd{1}, uint8([double('I'), double('P'), 0])));

    % Second read inside the TTL must be served from cache, even though the
    % underlying pin has changed.
    mock.setInput('P', 1, 1);
    v1 = mock.get_parameter('Port1In', includeInvisible = true);
    results(end+1,:) = check('Second read inside SnapshotInterval issues no ''I''', ...
        numel(mock.commandsOfType('I')) == 1);
    results(end+1,:) = check('Cached read returns the cached value', isequal(v0, v1));

    % Expiring the TTL must reach the device again.
    mock.SnapshotInterval = 0;
    v2 = mock.get_parameter('Port1In', includeInvisible = true);
    results(end+1,:) = check('Expired cache issues a fresh ''I''', ...
        numel(mock.commandsOfType('I')) == 2);

    % Polarity, stated as the property that can actually be verified offline:
    % the polled read must agree with the firmware's own event detector, which
    % raises PortNIn on a LOW->HIGH edge (Bpod_MainModule_0_6.ino:387) using the
    % same digitalReadDirect call that answers 'I'. A read that disagreed would
    % have Port1In reading false at the instant a Port1In event fires.
    results(end+1,:) = check('Port1In raw 0 reads false', ~logical(v0));
    results(end+1,:) = check('Port1In raw 1 reads true (agrees with the Port1In event)', ...
        logical(v2));
    skips(end+1,:) = skipped('Absolute IR beam polarity (which way is "beam broken"?)', ...
        ['needs a rig: it is a wiring fact, not a protocol fact. The protocol half is ' ...
         'settled -- Bpod_MainModule_0_6.ino:386-388 raises the Port<N>In event on a ' ...
         'LOW->HIGH edge, so readInput_ reporting raw HIGH as active agrees with the ' ...
         'event stream by construction, which is the property that actually matters. ' ...
         'What a bench check still has to establish is whether HIGH corresponds to an ' ...
         'occluded or an unoccluded beam on this rig''s photogates.']);

    % BNC sense is firmware-build dependent: high is raw 1 below build 7.
    mock.setInput('B', 1, 1);
    bv = mock.get_parameter('BNCIn1', includeInvisible = true);
    results(end+1,:) = check('BNCIn1 raw 1 reads true on firmware build 6', logical(bv));

    mock.SnapshotInterval = 5;
catch ME
    results(end+1,:) = check(['Input reads: ' ME.message], false);
end

%% 6. State matrix encoding
% A wrong matrix is SILENT: the firmware validates nothing, reads a fixed byte
% count derived from nStates, and runs whatever it decodes to. These are the
% checks that can be made without a rig.
%
% Uploaded through sendStateMatrix directly rather than through a trigger, so
% the encoder is tested independently of the trial-start path.
try
    mock.trigger('x_ResetTrig_1');
    mock.sendStateMatrix(Bpod_Mock.testStateMatrix(mock, struct()));
    payload = mock.LastMatrixPayload;

    nStates = 2;
    expectedLen = 1 + nStates*(40+17+5+5) + 5 + 8 + 4 + 4*(nStates+10);
    results(end+1,:) = check('Upload payload has the length the firmware reads', ...
        numel(payload) == expectedLen);
    results(end+1,:) = check('Payload starts with nStates', ...
        ~isempty(payload) && payload(1) == nStates);
    results(end+1,:) = check('Device acknowledged the upload', ...
        ~isempty(mock.commandsOfType('P')));

    if numel(payload) == expectedLen
        inRow1 = double(payload(2:41));
        inRow2 = double(payload(42:81));
        % BASE 0 and ROW MAJOR. Manifest order is add order: 1 WaitForPoke,
        % 2 Reward. Port1In (col 1) goes to Reward -> base-0 index 1.
        results(end+1,:) = check('InputMatrix is base-0 (Port1In -> state 2 sends 1)', ...
            inRow1(1) == 1);
        % Tup (col 40) exits -> nStates+1 = 3 -> base-0 index 2.
        results(end+1,:) = check('Exit target encodes as nStates (base-0 of nStates+1)', ...
            inRow1(40) == 2);
        % Every unmapped event is a self-reference.
        results(end+1,:) = check('Unmapped events self-reference in row 1', ...
            all(inRow1(2:39) == 0));
        results(end+1,:) = check('Row major: row 2 self-references state 2', ...
            all(inRow2(1:39) == 1) && inRow2(40) == 2);

        outRow1 = double(payload(82:98));
        outRow2 = double(payload(99:115));
        % OutputMatrix holds values, not state indices: no base-0 subtraction.
        results(end+1,:) = check('OutputMatrix is NOT base-0 (PWM1 column holds 255)', ...
            outRow1(10) == 255);
        results(end+1,:) = check('''Valve'',1 sets bit 0 of the valve column', ...
            outRow2(1) == 1);

        % 255 in the blank matrix means "no event attached" and is transmitted
        % as 254, the value the firmware tests against. The 254 literal in
        % GenerateBlankStateMatrix.m would send 253 and attach every unused
        % counter to event code 253.
        results(end+1,:) = check('Unused global counters transmit the 254 sentinel', ...
            all(double(payload(136:140)) == 254));
        results(end+1,:) = check('All 8 ports and 4 wires are enabled', ...
            all(double(payload(141:152)) == 1));

        ticks = double(typecast(uint8(payload(153:end)), 'uint32'));
        results(end+1,:) = check('State timers scale to 100 us ticks', ...
            numel(ticks) == 12 && ticks(1) == 10 * hw.Bpod.TICK_HZ && ...
            ticks(2) == 0.1 * hw.Bpod.TICK_HZ);
    end

    results(end+1,:) = check('StateNames follow manifest (add) order', ...
        isequal(mock.StateNames, {'WaitForPoke', 'Reward'}));

    % An unchanged matrix must cost one 'R' byte, not a whole re-upload.
    nUploads = numel(mock.commandsOfType('P'));
    mock.sendStateMatrix(Bpod_Mock.testStateMatrix(mock, struct()));
    results(end+1,:) = check('An unchanged matrix is not re-uploaded', ...
        numel(mock.commandsOfType('P')) == nUploads);

    % Uploading while a matrix is live is the hazard: 'P' is accepted mid-run by
    % the firmware and its acknowledgement byte would land inside the push
    % stream. Re-sending the SAME matrix is safe because the memo means nothing
    % reaches the wire; a CHANGED one has to be refused.
    mock.startTrialDirect(Bpod_Mock.testStateMatrix(mock, struct()));
    nP = numel(mock.commandsOfType('P'));
    noop = true;
    try
        mock.sendStateMatrix(Bpod_Mock.testStateMatrix(mock, struct()));
    catch
        noop = false;
    end
    results(end+1,:) = check('Re-sending an unchanged matrix mid-run writes nothing', ...
        noop && numel(mock.commandsOfType('P')) == nP);

    refused = '';
    try
        mock.sendStateMatrix(Bpod_Mock.testStateMatrix(mock, struct('WaitDuration', 5)));
    catch ME
        refused = ME.identifier;
    end
    results(end+1,:) = check('Uploading a CHANGED matrix mid-run is refused', ...
        strcmp(refused, 'hw:Bpod:UploadWhileRunning'));
    results(end+1,:) = check('A refused upload put no ''P'' on the wire', ...
        numel(mock.commandsOfType('P')) == nP);
    mock.abortMatrix();

    skips(end+1,:) = skipped('Encoder byte-for-byte equality with Bpod SendStateMatrix', ...
        ['needs a rig with the Bpod GUI running: SendStateMatrix.m reads ' ...
         'BpodSystem.InputsEnabled and writes GUIHandles.CxnDisplay, so it cannot be ' ...
         'executed here. Capture its BpodSerialWrite payload once and compare against ' ...
         'compileMatrix_, which is kept pure for exactly that comparison.']);
catch ME
    results(end+1,:) = check(['State matrix encoding: ' ME.message], false);
end

%% 7. The load-bearing test: a non-blocking trial driven by fragments
goldenStream = [Bpod_Mock.eventMessage(0), ...      % Port1In  (0-based 0)
                Bpod_Mock.eventMessage(39), ...     % Tup      (0-based 39)
                Bpod_Mock.endSentinel(), ...        % [1 1 255]
                Bpod_Mock.epilogueBytes(12345, 0, [5000 6000])];
goldenRef = struct();
try
    mock.trigger('x_ResetTrig_1');

    % The real trial-start path, asserted on its own before anything depends on
    % it. When this fails every trial below is started through the mock's
    % scaffold instead, so the pump is still covered and the defect still shows.
    startErr = '';
    t = NaN;
    tStart = tic;
    try
        t = mock.trigger('x_NewTrial_1');
    catch ME
        startErr = ME.identifier;
        mock.startTrialDirect(Bpod_Mock.testStateMatrix(mock, struct()));
    end
    % Timed around whichever start path ran, so the non-blocking claim below is
    % about a trial that actually started.
    elapsed = toc(tStart);

    results(end+1,:) = check('trigger(''x_NewTrial_'') starts a trial without throwing', ...
        isempty(startErr));
    if isempty(startErr)
        % The trigger's own return type is re-checked in its own section; here
        % it matters that a started trial handed back a usable timestamp.
        results(end+1,:) = check('trigger returns a finite (1,1) double', ...
            isa(t, 'double') && isscalar(t) && isfinite(t));
    else
        fprintf(['  NOTE  trigger(''x_NewTrial_1'') raised %s. startTrial_ calls ' ...
            'compileMatrix_ on the\n        matrix it just built, but sma.nStates is ' ...
            'written by sendStateMatrix AFTER it permutes\n        into manifest order, ' ...
            'so nStates is still 0. Trials below use the mock''s scaffold.\n'], startErr);
    end

    % The whole point of replacing RunStateMatrix: the start returns while the
    % trial is still in flight, instead of spinning in `while InStateMatrix`.
    results(end+1,:) = check('Trial start does not block for the trial', elapsed < 0.5);
    rec = mock.trialRecord();
    results(end+1,:) = check('Trial start left the matrix running', rec.matrixRunning);
    results(end+1,:) = check('Trial start did not latch trial completion', ~rec.trialComplete);
    results(end+1,:) = check('Device received ''R''', mock.RunCount >= 1);

    logAtStart = numel(mock.Log);

    % Fragment sizes. Zeros are deliberately empty pumps; the epilogue's 10-byte
    % header is split 6/4 across two of them.
    fragments = [3, 0, 0, 0, 3, 3, 6, 4, 8];
    results(end+1,:) = check('Fragment plan covers the whole stream', ...
        sum(fragments) == numel(goldenStream));

    mock.stage(goldenStream);
    completeFlags = zeros(1, numel(fragments));
    for k = 1:numel(fragments)
        mock.release(fragments(k));
        mock.pump();
        completeFlags(k) = mock.get_parameter('x_TrialComplete_1', includeInvisible = true);
        if k < numel(fragments)
            % Poll an input line while the matrix is live. The interlock must
            % keep this off the wire: 'I' answers with a bare, unframed byte
            % that the pump would read as an opcode.
            mock.get_parameter('Port1In', includeInvisible = true);
        end
    end

    results(end+1,:) = check('x_TrialComplete_ stays false until the epilogue lands', ...
        all(completeFlags(1:end-1) == 0));
    results(end+1,:) = check('x_TrialComplete_ latches true on the final fragment', ...
        completeFlags(end) == 1);
    results(end+1,:) = check('No ''I'' was issued while the matrix was live', ...
        ~any(strcmp(mock.logOpcodes(logAtStart + 1), 'I')));

    % ... and the interlock releases once the trial is over.
    mock.SnapshotInterval = 0;
    nI = numel(mock.commandsOfType('I'));
    mock.get_parameter('Port1In', includeInvisible = true);
    results(end+1,:) = check('Input reads resume after the trial closes', ...
        numel(mock.commandsOfType('I')) == nI + 1);
    mock.SnapshotInterval = 5;

    rec = mock.trialRecord();
    goldenRef = decodeOf(rec);

    results(end+1,:) = check('Decoded StateCodes == [1 2]',      isequal(rec.stateCodes, [1 2]));
    results(end+1,:) = check('Decoded EventCodes == [1 40]',     isequal(rec.eventCodes, [1 40]));
    results(end+1,:) = check('Decoded EventTimestamps == [0.5 0.6] s', ...
        isequal(rec.eventTimes, [0.5 0.6]));
    results(end+1,:) = check('Decoded StateTimestamps == [0 0.5 0.6] s', ...
        isequal(rec.stateTimes, [0 0.5 0.6]));
    results(end+1,:) = check('Parser consumed the stream exactly', rec.rxPending == 0);
    results(end+1,:) = check('Parser left no run state behind', ...
        ~rec.matrixRunning && ~rec.awaitingEpilogue);
    results(end+1,:) = check('Trial is not marked aborted',      ~rec.trialAborted);
    results(end+1,:) = check('Event and timestamp counts agreed', ...
        isfield(rec.results, 'EventCountMismatch') && ~rec.results.EventCountMismatch);
catch ME
    results(end+1,:) = check(['Non-blocking trial: ' ME.message], false);
end

%% 8. Byte-split fuzz — the property the whole architecture rests on
try
    n = numel(goldenStream);
    firstBad = 0;
    for splitAt = 0:n
        rec = runGoldenTrial(mock, goldenStream, [splitAt, n - splitAt]);
        if ~isequaln(decodeOf(rec), goldenRef)
            firstBad = splitAt;
            break
        end
    end
    results(end+1,:) = check('Identical decode at every single-byte split point', ...
        firstBad == 0);
    if firstBad > 0
        fprintf('  NOTE  first divergent split boundary: byte %d of %d\n', firstBad, n);
    end

    rec = runGoldenTrial(mock, goldenStream, ones(1, n));
    results(end+1,:) = check('Identical decode delivered one byte at a time', ...
        isequaln(decodeOf(rec), goldenRef));

    rng(20260805, 'twister');
    badRandom = 0;
    for trial = 1:12
        chunks = randomChunks(n);
        rec = runGoldenTrial(mock, goldenStream, chunks);
        if ~isequaln(decodeOf(rec), goldenRef)
            badRandom = trial;
            break
        end
    end
    results(end+1,:) = check('Identical decode under 12 random chunkings', badRandom == 0);
catch ME
    results(end+1,:) = check(['Byte-split fuzz: ' ME.message], false);
end

%% 9. trigger returns a value assignable into hw.Parameter.lastUpdated
try
    P = mock.find_parameter('x_ResetTrig_1', includeInvisible = true);
    t = mock.trigger('x_ResetTrig_1');
    results(end+1,:) = check('trigger returns a (1,1) double', ...
        isa(t, 'double') && isscalar(t) && isreal(t));
    % hw.Parameter.Trigger assigns straight into lastUpdated (1,1) double, so a
    % datetime here would throw inside the runtime's dispatch loop.
    P.lastUpdated = t;
    results(end+1,:) = check('trigger result assigns into lastUpdated', ...
        isequal(P.lastUpdated, t));
    results(end+1,:) = check('An unknown trigger name is benign', ...
        isa(mock.trigger('NoSuchTrigger'), 'double'));
catch ME
    results(end+1,:) = check(['trigger return type: ' ME.message], false);
end

%% 10. Trial-result parameters must resolve through get_parameter
% This is the DATA contract: ep_TimerFcn_RunTime sweeps every readable parameter
% at trial end and stores the result. A result name the read path does not
% recognize falls through to the parameter's own stored value, which is empty —
% silently, with the trial record still sitting in the interface.
try
    rec = runGoldenTrial(mock, goldenStream, numel(goldenStream));
    expected = { ...
        'RespCode',             double(epsych.BitMask.Bits2Mask(double(epsych.BitMask.Reward)))
        'RespLatency',          0.5
        'nStatesVisited',       2
        'LastStateCode',        2
        'LastStateName',        'Reward'
        'TrialStartTimestamp',  12.345
        'TrialDuration_Actual', 0.6
        'Aborted',              false
        'LastSoftCode',         0
        'StateCodes',           [1 2]
        'StateTimestamps',      [0 0.5 0.6]
        'EventCodes',           [1 40]
        'EventTimestamps',      [0.5 0.6]};

    unreachable = {};
    for k = 1:size(expected, 1)
        name = expected{k, 1};
        want = expected{k, 2};
        got = mock.get_parameter(name);
        if islogical(want) || isnumeric(want)
            ok = isequaln(double(got), double(want));
        else
            ok = isequal(got, want);
        end
        results(end+1,:) = check(sprintf('Result parameter %s reads the trial record', name), ok);
        % A miss whose value IS sitting in the latched record means the name
        % simply is not wired into get_parameter's decoder, not that the pump
        % failed to decode it. Worth separating, because the two have very
        % different fixes.
        if ~ok && isfield(rec.results, name)
            unreachable{end + 1} = name;
        end
    end
    if ~isempty(unreachable)
        fprintf(['  NOTE  %d result value(s) are latched in the interface but unreachable ' ...
            'through\n        get_parameter: %s.\n        populateModule_ publishes these ' ...
            'names; get_parameter''s decodeName_ lists a different\n        set ' ...
            '(TrialAborted, NStates, StateTimes, EventTimes, CurrentState, ...), so they ' ...
            'fall\n        through to the parameter''s own stored value and DATA records ' ...
            'empty.\n'], numel(unreachable), strjoin(unreachable, ', '));
    end

    % TrialDuration is a WRITABLE configuration parameter (a trial-table column)
    % that also echoes into DATA, so the value written for the trial must read
    % back unchanged.
    Pd = mock.find_parameter('TrialDuration');
    Pd.Value = 0.75;
    results(end+1,:) = check('Writable TrialDuration round-trips its configured value', ...
        isequaln(mock.get_parameter('TrialDuration'), 0.75));

    results(end+1,:) = check('Host-side TrialType round-trips', ...
        localRoundTrip(mock, 'TrialType', 3));

    % parameterStruct is what a state-matrix builder receives. Reading a
    % write-only parameter returns NaN and logs a red "is a write-only
    % parameter" line through hw.Parameter.get.Value — twice per trial, forever,
    % for Serial1Byte and Serial2Byte.
    S = mock.builderStruct();
    results(end+1,:) = check(['parameterStruct omits write-only parameters ' ...
        '(they read NaN and log red, once per channel per trial)'], ...
        ~isfield(S, 'Serial1Byte') && ~isfield(S, 'Serial2Byte'));
    results(end+1,:) = check('parameterStruct exposes the trial configuration', ...
        isfield(S, 'TrialDuration') && isfield(S, 'TrialType'));
    results(end+1,:) = check('parameterStruct includes invisible I/O lines', ...
        isfield(S, 'Valve1') && isfield(S, 'PWM1') && isfield(S, 'Port1In'));
catch ME
    results(end+1,:) = check(['Trial-result parameters: ' ME.message], false);
end

%% 11. The readable field set must be frozen across trials
% RUNTIME.TRIALS(i).DATA(k) = data throws "Subscripted assignment between
% dissimilar structures" the moment one trial reports a different set of fields
% than another, and takes the session down at a trial boundary.
try
    % Trial A visits WaitForPoke -> Reward; trial B times out of WaitForPoke and
    % never enters Reward, so it visits a different set of states.
    streamB = [Bpod_Mock.eventMessage(39), Bpod_Mock.endSentinel(), ...
               Bpod_Mock.epilogueBytes(20000, 0, 4000)];

    runGoldenTrial(mock, goldenStream, numel(goldenStream));
    dataA = dataSweep(mock);
    recB = runGoldenTrial(mock, streamB, numel(streamB));
    dataB = dataSweep(mock);

    results(end+1,:) = check('Trial B really took a different path', ...
        isequal(recB.stateCodes, 1) && isequal(recB.eventCodes, 40));
    results(end+1,:) = check('DATA sweep reports the same fields on both trials', ...
        isequal(fieldnames(dataA), fieldnames(dataB)));

    clear DATA
    frozen = true;
    try
        DATA(1) = dataA;
        DATA(2) = dataB;
        frozen = numel(DATA) == 2;
    catch
        frozen = false;
    end
    results(end+1,:) = check('DATA(k) = data assignment survives both trials', frozen);

    % Trial config columns and DATA fields are two different filters over one
    % table; getting them backwards is silent.
    trialTable = mock.all_parameters(Access = 'Write');
    tableNames = sort({trialTable.Name});
    results(end+1,:) = check('Trial table is exactly {TrialDuration, TrialType}', ...
        isequal(tableNames, {'TrialDuration', 'TrialType'}));
    results(end+1,:) = check('DATA sweep carries 16 fields (2 config + 14 results)', ...
        numel(fieldnames(dataA)) == 16);
catch ME
    results(end+1,:) = check(['Frozen field set: ' ME.message], false);
end

%% 12. Abort drains the burst the firmware still sends
% `if (MatrixFinished)` sits OUTSIDE `if (RunningStateMatrix)`, so 'X' still
% emits the full sentinel + 10-byte header + timestamp block. Bytes left behind
% are read as the NEXT trial's events, and epsych.Runtime.delete leaves
% interfaces connected for reuse, so they outlive the session that made them.
try
    mock.trigger('x_ResetTrig_1');
    mock.RunScript = Bpod_Mock.eventMessage(0);
    try
        mock.trigger('x_NewTrial_1');
    catch
        mock.startTrialDirect(Bpod_Mock.testStateMatrix(mock, struct()));
    end
    mock.release(inf);
    mock.pump();

    mock.AbortTimestamps = [1000 2000];
    nX = mock.AbortCount;
    mock.abortMatrix();

    results(end+1,:) = check('abortMatrix sends ''X''', mock.AbortCount == nX + 1);
    results(end+1,:) = check('Abort burst was fully consumed', mock.bufferedCount() == 0);
    results(end+1,:) = check('Device has nothing left staged',  mock.stagedCount() == 0);

    rec = mock.trialRecord();
    results(end+1,:) = check('Abort clears the parser buffer', rec.rxPending == 0);
    results(end+1,:) = check('Abort clears the run state', ...
        ~rec.matrixRunning && ~rec.awaitingEpilogue);
    % Marking the trial complete is what keeps the runtime from waiting forever
    % on an x_TrialComplete_ the device will never raise.
    results(end+1,:) = check('Abort marks the trial aborted and complete', ...
        rec.trialAborted && rec.trialComplete);
    results(end+1,:) = check('Abort recovers the partial trial timestamps (seconds)', ...
        isequal(rec.eventTimes, [0.1 0.2]));

    % The real proof: the next run must decode exactly like a clean one.
    recNext = runGoldenTrial(mock, goldenStream, numel(goldenStream));
    results(end+1,:) = check('The run after an abort starts from a clean buffer', ...
        isequaln(decodeOf(recNext), goldenRef));
catch ME
    results(end+1,:) = check(['Abort drain: ' ME.message], false);
end

%% 12b. An aborted trial must publish ITS OWN results
% get_parameter serves every result parameter out of obj.inputCache_, and only
% finalizeTrial_ writes that cache. An abort that merely latched trialComplete_
% left the PREVIOUS trial's frozen set sitting there, so the stopped trial was
% saved with that trial's states, its RespCode, its timestamps -- and with
% Aborted = false. Nothing in DATA said the trial never finished, which is why
% this is asserted against a preceding COMPLETED trial rather than against a
% fresh interface: only a cache holding a plausible result set can shadow one.
try
    % 1. A clean trial: WaitForPoke -> Reward, two states, not aborted.
    runGoldenTrial(mock, goldenStream, numel(goldenStream));

    % RESULT_PARAMETERS names the frozen set, but populateModule_ does not
    % publish a parameter for every one of them, so read only what the module
    % actually carries rather than warning once per missing name.
    resultNames = hw.Bpod.RESULT_PARAMETERS;
    resultNames = resultNames(cellfun(@(n) ~isempty( ...
        mock.find_parameter(n, silenceParameterNotFound = true)), resultNames));

    doneRef = struct();
    for k = 1:numel(resultNames)
        doneRef.(resultNames{k}) = mock.get_parameter(resultNames{k});
    end
    dataDone = dataSweep(mock);
    results(end+1,:) = check('Setup: the completed trial reads Aborted == false', ...
        ~doneRef.Aborted && isequal(doneRef.nStatesVisited, 2));

    % 2. A second trial aborted mid-flight. Tup in WaitForPoke targets 'exit',
    %    which the pump does not record as a state, so this trial genuinely
    %    visits a different set of states than the one above and every result
    %    field below distinguishes the two.
    mock.trigger('x_ResetTrig_1');
    mock.RunScript = Bpod_Mock.eventMessage(39);   % Tup (0-based 39)
    try
        mock.trigger('x_NewTrial_1');
    catch
        mock.startTrialDirect(Bpod_Mock.testStateMatrix(mock, struct()));
    end
    mock.release(inf);
    mock.pump();

    results(end+1,:) = check('Setup: the second trial is in flight before the abort', ...
        mock.trialRecord().matrixRunning);

    mock.AbortTimestamps = 3000;   % 0.3 s, one timestamp for the one event
    mock.abortMatrix();

    abortedMask = double(epsych.BitMask.Bits2Mask(double(epsych.BitMask.Abort)));

    results(end+1,:) = check('THE BUG: get_parameter(''Aborted'') is true after an abort', ...
        logical(mock.get_parameter('Aborted')));
    results(end+1,:) = check('Aborted trial does not report the completed trial''s states', ...
        isequal(mock.get_parameter('nStatesVisited'), 1) && ...
        isequal(mock.get_parameter('StateCodes'), 1));
    results(end+1,:) = check('Aborted trial reports its own last state', ...
        strcmp(mock.get_parameter('LastStateName'), 'WaitForPoke') && ...
        isequaln(mock.get_parameter('LastStateCode'), 1));
    results(end+1,:) = check('Aborted trial reports its own events', ...
        isequal(mock.get_parameter('EventCodes'), 40) && ...
        isequal(mock.get_parameter('EventTimestamps'), 0.3));
    results(end+1,:) = check('Aborted trial reports its own trial timing', ...
        isequaln(mock.get_parameter('TrialStartTimestamp'), 0) && ...
        isequaln(mock.get_parameter('TrialDuration_Actual'), 0.3));
    % The Abort bit is what psychophysics code scores on, so a RespCode carried
    % over from a rewarded trial would count an aborted trial as a hit.
    results(end+1,:) = check('Aborted trial RespCode carries the Abort bit only', ...
        isequal(double(mock.get_parameter('RespCode')), abortedMask));
    results(end+1,:) = check('Aborted trial did not inherit the completed trial''s RespCode', ...
        ~isequal(double(mock.get_parameter('RespCode')), double(doneRef.RespCode)));

    % Every result parameter, not just the ones spelled out above: none may
    % still be answering with the completed trial's value.
    stale = {};
    for k = 1:numel(resultNames)
        nm = resultNames{k};
        if ~isequaln(mock.get_parameter(nm), doneRef.(nm))
            continue
        end
        % Two fields legitimately match because both trials share the same
        % value, so they cannot distinguish a fresh record from a carried-over
        % one: neither trial emitted a soft code, and neither overran
        % MAX_TIMESTAMPS. Excluding them keeps the check honest rather than
        % weakening it -- every other field must differ.
        if ~any(strcmp(nm, {'LastSoftCode', 'EventCountMismatch'}))
            stale{end + 1} = nm;
        end
    end
    results(end+1,:) = check('No result parameter still answers with the completed trial''s value', ...
        isempty(stale));
    if ~isempty(stale)
        fprintf('  NOTE  stale after abort: %s\n', strjoin(stale, ', '));
    end

    % An aborted trial still has to land in DATA, so its field set must match a
    % completed trial's exactly.
    dataAborted = dataSweep(mock);
    results(end+1,:) = check('Aborted trial keeps the DATA field set frozen', ...
        isequal(fieldnames(dataDone), fieldnames(dataAborted)));
    clear DATA
    stored = false;
    try
        DATA(1) = dataDone;
        DATA(2) = dataAborted;
        stored = numel(DATA) == 2 && logical(DATA(2).Aborted) && ~logical(DATA(1).Aborted);
    catch
        stored = false;
    end
    results(end+1,:) = check('DATA records the abort as aborted and the completion as complete', ...
        stored);
catch ME
    results(end+1,:) = check(['Aborted trial results: ' ME.message], false);
end

%% 13. selfTest
try
    callsBefore = mock.TransportCalls;
    logBefore = numel(mock.Log);
    r = mock.selfTest();
    results(end+1,:) = check('selfTest returns results', ~isempty(r));
    results(end+1,:) = check('selfTest statuses are valid', ...
        all(ismember(string({r.status}), ["pass","fail","warn","info","skip"])));
    results(end+1,:) = check('selfTest results are well formed', ...
        all(isfield(r, {'name', 'status', 'summary', 'detail', 'remedy'})));
    % Non-invasive means NO transport at all: epsych.SelfTest can be opened from
    % RunExpt's Help menu mid-session, and a stray probe byte would be parsed as
    % an opcode by the pump or answered with a bare byte the pump would misread.
    results(end+1,:) = check('Non-invasive selfTest issues zero transport calls', ...
        mock.TransportCalls == callsBefore);
    results(end+1,:) = check('Non-invasive selfTest writes no commands', ...
        numel(mock.Log) == logBefore);
    results(end+1,:) = check('Non-invasive selfTest skips the handshake check', ...
        any(strcmp(string({r.status}), "skip")));

    r2 = mock.selfTest(Invasive = true);
    results(end+1,:) = check('Invasive selfTest on a live link keeps it connected', ...
        mock.IsConnected);
    results(end+1,:) = check('Invasive selfTest reports the handshake', ...
        any(contains(string({r2.name}), "Handshake")));

    m3 = Bpod_Mock(Connect = false);
    r3 = m3.selfTest(Invasive = true);
    results(end+1,:) = check('Invasive selfTest restores a disconnected interface', ...
        ~m3.IsConnected);
    results(end+1,:) = check('Invasive selfTest from offline still returns results', ...
        ~isempty(r3));
    delete(m3)
catch ME
    results(end+1,:) = check(['selfTest: ' ME.message], false);
end

%% 14. Modules
try
    thrown = '';
    try
        mock.setModules(hw.Module(mock, 'Extra', 'Extra', uint8(2)));
    catch ME
        thrown = ME.identifier;
    end
    results(end+1,:) = check('setModules refuses while connected', ...
        strcmp(thrown, 'hw:Bpod:ModulesWhileConnected'));

    % The silent-clobber regression: Protocol.createInterfaceFromStruct_ installs
    % authored modules with setModules BEFORE connecting, and ProtocolDesigner
    % does the same on Modify. Rebuilding obj.Module in setup_interface would
    % throw those hw.Parameter handles — and their authored trial levels — away
    % without erroring, so the session would silently run regenerated defaults.
    m4 = Bpod_Mock(Connect = false);
    mod = hw.Module(m4, 'Bpod', 'Bpod', uint8(1));
    authored = mod.add_parameter('TrialDuration', [0.25 0.5 1.0], ...
        Type = 'Float', Access = 'Any', Unit = 's');
    m4.setModules(mod);
    results(end+1,:) = check('setModules accepts while disconnected', numel(m4.Module) == 1);

    m4.connect();
    results(end+1,:) = check('Connect preserved the single module', numel(m4.Module) == 1);
    results(end+1,:) = check('Connect preserved the module handle', m4.Module(1) == mod);
    results(end+1,:) = check('Connect preserved the authored parameter handle', ...
        mod.Parameters(1) == authored);
    results(end+1,:) = check('Connect preserved the authored trial levels', ...
        numel(authored.Values) == 3);
    results(end+1,:) = check('Merge added no duplicate TrialDuration', ...
        numel(m4.find_parameter('TrialDuration', includeInvisible = true)) == 1);
    results(end+1,:) = check('Parameter table holds 59 parameters', ...
        numel(mod.Parameters) == 59);

    [tf, msg] = m4.readHardwareParameters(mod);
    results(end+1,:) = check('readHardwareParameters succeeds', tf);
    results(end+1,:) = check('readHardwareParameters is idempotent under merge', ...
        numel(mod.Parameters) == 59);
    results(end+1,:) = check('readHardwareParameters reports a message', ~isempty(msg));
    results(end+1,:) = check('canReadHardwareParameters accepts the owning module', ...
        m4.canReadHardwareParameters(mod));
    results(end+1,:) = check('canReadHardwareParameters rejects a foreign module', ...
        ~m4.canReadHardwareParameters(hw.Module(m4, 'Aux', 'Aux', uint8(9))));

    m4.disconnect();
    delete(m4)
catch ME
    results(end+1,:) = check(['Modules: ' ME.message], false);
end

%% 15. prepareRecording refuses a multi-subject session
% Bpod has one state machine and one 'R' opcode, and Protocol.addInterface
% rejects a second interface of the same Type with only a vprintf, so subject 2
% would clobber subject 1's in-flight matrix with no error at all.
try
    stub2 = Bpod_Mock.runtimeStub(2);
    thrown = '';
    try
        mock.prepareRecording(stub2);
    catch ME
        thrown = ME.identifier;
    end
    delete(stub2)
    results(end+1,:) = check('prepareRecording errors for NSubjects > 1', ...
        strcmp(thrown, 'hw:Bpod:MultipleSubjects'));

    stub1 = Bpod_Mock.runtimeStub(1);
    mock.prepareRecording(stub1);
    delete(stub1)
    results(end+1,:) = check('prepareRecording accepts a single subject', true);

    mock.prepareRecording([]);
    results(end+1,:) = check('prepareRecording tolerates an empty runtime', true);
catch ME
    results(end+1,:) = check(['prepareRecording: ' ME.message], false);
end

%% 16. Disconnect drives outputs low
% Animal welfare, not cleanup: the firmware resets valves only on a clean matrix
% end or on 'X', so a session that errors mid-trial leaves a valve energized.
try
    mock.set_parameter('Valve2', 1);
    results(end+1,:) = check('Valve2 is energized before disconnect', ...
        mock.DeviceOutputs.V == 2);

    mock.resetLog();
    mock.disconnect();

    results(end+1,:) = check('disconnect clears IsConnected', ~mock.IsConnected);
    results(end+1,:) = check('disconnect drove every output group low', ...
        mock.DeviceOutputs.V == 0 && mock.DeviceOutputs.B == 0 && ...
        mock.DeviceOutputs.W == 0 && all(mock.DeviceOutputs.P == 0));
    results(end+1,:) = check('disconnect emitted ''Z''', ...
        any(strcmp(mock.logOpcodes(), 'Z')));
    zIdx = find(strcmp(mock.logOpcodes(), 'Z'), 1);
    results(end+1,:) = check('Outputs were dropped BEFORE ''Z''', ...
        ~isempty(zIdx) && any(strcmp(mock.logOpcodes(), 'O')) && ...
        find(strcmp(mock.logOpcodes(), 'O'), 1) < zIdx);

    mock.disconnect();
    results(end+1,:) = check('A second disconnect does not throw', true);
    results(end+1,:) = check('Reads after disconnect do not throw', ...
        isa(mock.get_parameter('Valve2', includeInvisible = true), 'double') || true);
    results(end+1,:) = check('mode after disconnect is still readable', ...
        isa(mock.mode, 'hw.DeviceState'));
catch ME
    results(end+1,:) = check(['Disconnect: ' ME.message], false);
end

%% Summary
labels = results(:,1);
passed = cell2mat(results(:,2));
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
for i = 1:size(skips, 1)
    fprintf('  SKIP  %s\n          reason: %s\n', skips{i,1}, skips{i,2});
end
fprintf('\n%d passed, %d failed, %d skipped, %d total\n\n', ...
    sum(passed), sum(~passed), size(skips, 1), numel(passed));

if any(~passed)
    error('smoke_test_bpod:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end


function row = skipped(label, reason)
% row = skipped(label, reason)
% Record one un-runnable assertion as a {label, reason} row. Used only where a
% claim genuinely cannot be settled without hardware.
row = {label, reason};
end


function c = controlTypeOf(spec, optionName)
% c = controlTypeOf(spec, optionName)
% controlType of one named hw.InterfaceSpecOption, or '' when absent.
c = '';
idx = find(strcmp({spec.options.name}, optionName), 1);
if ~isempty(idx)
    c = char(spec.options(idx).controlType);
end
end


function rec = runGoldenTrial(mock, stream, chunkSizes)
% rec = runGoldenTrial(mock, stream, chunkSizes)
% Run one trial, handing the pump `stream` in the given fragment sizes.
%
% Mirrors the runtime's own order: ResetTrig clears the record and resyncs the
% link, then NewTrial builds, uploads if changed, and starts the matrix. Bytes
% are staged only afterwards, because ResetTrig flushes the input buffer.
%
% Prefers the real trigger and falls back to the mock's scaffold only when it
% throws, so the fallback disappears by itself once trigger's startTrial_ stops
% compiling an unpermuted matrix. The failure is asserted in its own check.
mock.trigger('x_ResetTrig_1');
try
    mock.trigger('x_NewTrial_1');
catch
    mock.startTrialDirect(Bpod_Mock.testStateMatrix(mock, struct()));
end
mock.stage(stream);
for k = 1:numel(chunkSizes)
    mock.release(chunkSizes(k));
    mock.pump();
end
mock.release(inf);
mock.pump();
rec = mock.trialRecord();
end


function d = decodeOf(rec)
% d = decodeOf(rec)
% Reduce a trial record to the fields a decode must reproduce exactly.
%
% Excludes trialNum and the output shadow, which legitimately advance from run
% to run, so the fuzz comparison tests the parser and nothing else.
d = struct( ...
    'stateCodes',  rec.stateCodes, ...
    'stateTimes',  rec.stateTimes, ...
    'eventCodes',  rec.eventCodes, ...
    'eventTimes',  rec.eventTimes, ...
    'complete',    rec.trialComplete, ...
    'aborted',     rec.trialAborted, ...
    'softCode',    rec.lastSoftCode, ...
    'rxPending',   rec.rxPending, ...
    'results',     localResultFields(rec.results));
end


function s = localResultFields(results)
% s = localResultFields(results)
% Pull the published trial results out of inputCache_, which also carries the
% input snapshot cache and writeOutputs_'s last-written masks.
names = {'TrialStartTimestamp', 'TrialDuration_Actual', 'nStatesVisited', ...
    'LastStateCode', 'LastStateName', 'LastSoftCode', 'Aborted', 'RespCode', ...
    'RespLatency', 'EventCountMismatch', 'StateCodes', 'StateTimestamps', ...
    'EventCodes', 'EventTimestamps'};
s = struct();
for k = 1:numel(names)
    if isstruct(results) && isfield(results, names{k})
        s.(names{k}) = results.(names{k});
    else
        s.(names{k}) = [];
    end
end
end


function d = dataSweep(mock)
% d = dataSweep(mock)
% Reproduce the per-trial DATA sweep ep_TimerFcn_RunTime performs.
%
% RUNTIME.all_parameters(Access='Read', asStruct=true, valueOnly=true) resolves
% to the same filter at interface level: Visible == true && Access ~= 'Write'.
P = mock.all_parameters(Access = 'Read');
d = struct();
for k = 1:numel(P)
    d.(P(k).validName) = P(k).Value;
end
end


function tf = localRoundTrip(mock, name, value)
% tf = localRoundTrip(mock, name, value)
% Write a host-side parameter the way the runtime does and read it back.
P = mock.find_parameter(name, includeInvisible = true);
P.Value = value;
tf = isequaln(mock.get_parameter(name, includeInvisible = true), value);
end


function chunks = randomChunks(n)
% chunks = randomChunks(n)
% Partition n bytes into random fragments, sprinkled with empty pumps.
%
% Every fragment takes at least one byte so the partition terminates; the empty
% pumps that model a tick with no traffic are inserted separately.
chunks = zeros(1, 0);
remaining = n;
while remaining > 0
    if rand < 0.3
        chunks(end + 1) = 0;
    end
    take = randi([1, remaining]);
    chunks(end + 1) = take;
    remaining = remaining - take;
end
chunks(end + 1) = 0;
end
