% smoke_test_intan_rhx_protocol.m
% Mock-server smoke tests for hw.Intan_RHX — exercises the TCP command grammar
% and lifecycle without real hardware, via tmp/Intan_RHX_Mock (which overrides
% the byte-level transport seam). No Instrument Control Toolbox required.
%
% These tests target exactly the behaviors that the previous all-offline test
% could not reach — above all, that a "set" returns immediately instead of
% blocking for Timeout seconds (the shipped root bug).

fprintf('\n=== hw.Intan_RHX Mock/Protocol Smoke Test ===\n\n');

function assert_ok(label, expr)
    if expr
        fprintf('  PASS  %s\n', label);
    else
        fprintf('  FAIL  %s\n', label);
        error('smoke:fail', 'Assertion failed: %s', label);
    end
end

function rt = makeRuntime(dataFilename, isTest)
    rt = epsych.Runtime;
    rt.dfltDataPath = "C:/IntanData";
    rt.isTest = isTest;
    rt.SessionDataFilename = string(dataFilename);
end

REMOTE = '10.0.0.5';   % non-local host so prepareRecording skips local mkdir

%% 1. Root-bug regression: a set returns immediately (no blocking read)
try
    m = Intan_RHX_Mock(); m.connect();
    m.add_parameter('fileformat', 'Traditional');
    t = tic; m.set_parameter('fileformat', 'Traditional'); el = toc(t);
    assert_ok(sprintf('set_parameter returns fast (%.3fs < 0.1s)', el), el < 0.1);
    % And the char value is sent whole, not split per character (num2cell bug)
    assert_ok('char value sent whole', any(m.Log == "set fileformat Traditional"));
catch ME
    fprintf('  FAIL  set timing: %s\n', ME.message);
end

%% 2. Successful set emits no error/warning text
try
    m = Intan_RHX_Mock(); m.connect();
    m.add_parameter('fileformat', 'Traditional');
    out = evalc("m.set_parameter('fileformat','Traditional');");
    assert_ok('no error/fail/timeout text on success', isempty(regexpi(out, 'error|fail|timed out|discard', 'once')));
catch ME
    fprintf('  FAIL  set output: %s\n', ME.message);
end

%% 3. Exact bytes: forward slashes, no terminator, one command per write
try
    m = Intan_RHX_Mock(REMOTE); m.connect(); m.resetLog();
    m.RecordingRootDir = 'C:\IntanData';   % setter normalizes backslashes
    rt = makeRuntime("C:/IntanData/Rat1/Rat1_260716T101530.mat", false);
    m.prepareRecording(rt);
    assert_ok('filename.path exact bytes',        any(m.Log == "set filename.path C:/IntanData/Rat1"));
    assert_ok('filename.basefilename exact bytes',any(m.Log == "set filename.basefilename Rat1_260716T101530"));
    % No command carries a trailing newline or a ';' separator
    assert_ok('no newline in commands', ~any(contains(m.Log, newline)));
    assert_ok('no semicolon batching',  ~any(contains(m.Log, ';')));
catch ME
    fprintf('  FAIL  exact bytes: %s\n', ME.message);
end

%% 4. Mode change blocks until confirmed; exactly one 'set runmode record'
try
    m = Intan_RHX_Mock(); m.connect(); m.resetLog();
    m.setReplies('get runmode', {'Return: RunMode Stop', 'Return: RunMode Stop', 'Return: RunMode Record'});
    m.mode = hw.DeviceState.Record;
    assert_ok('exactly one set runmode record', m.logCount('set runmode record') == 1);
    assert_ok('mode reads Record after confirm', m.mode == hw.DeviceState.Record);
catch ME
    fprintf('  FAIL  mode confirm: %s\n', ME.message);
end

%% 5. runmode is not sent until uploadinprogress is False
try
    m = Intan_RHX_Mock(); m.connect(); m.resetLog();
    m.setReplies('get uploadinprogress', { ...
        'Return: UploadInProgress True', 'Return: UploadInProgress True', 'Return: UploadInProgress False'});
    m.setReplies('get runmode', {'Return: RunMode Record'});   % confirm quickly after upload idle
    m.mode = hw.DeviceState.Record;
    setIdx = find(m.Log == "set runmode record", 1);
    upBefore = sum(m.Log(1:setIdx-1) == "get uploadinprogress");
    assert_ok('runmode waits for upload idle (3 polls first)', upBefore == 3);
catch ME
    fprintf('  FAIL  upload guard: %s\n', ME.message);
end

%% 6. ActiveRecordingFile reconstructed from the RHX timestamp
try
    m = Intan_RHX_Mock(REMOTE);
    m.setReplies('get type', {'Return: Type ControllerRecordUSB3'});   % -> .rhd
    m.connect(); m.resetLog();
    m.RecordingRootDir = 'C:/IntanData';
    rt = makeRuntime("C:/IntanData/Rat1/Rat1_260716T101530.mat", false);
    m.prepareRecording(rt);
    m.setReplies('get runmode', {'Return: RunMode Stop', 'Return: RunMode Record'});
    m.setReplies('get filename.activefiletimestamp', { ...
        'Return: FileName.ActiveFileTimestamp RecordingNotStarted', ...
        'Return: FileName.ActiveFileTimestamp 260716_101530'});
    m.mode = hw.DeviceState.Record;
    assert_ok('ActiveRecordingFile reconstructed', ...
        endsWith(m.ActiveRecordingFile, 'Rat1_260716T101530_260716_101530.rhd'));
catch ME
    fprintf('  FAIL  active file: %s\n', ME.message);
end

%% 7. Spaces in the target abort a Record run; nothing hits the wire
try
    m = Intan_RHX_Mock(REMOTE); m.connect(); m.resetLog();
    m.RecordingRootDir = 'C:/IntanData';
    rtRec = makeRuntime("C:/IntanData/Rat 1/Rat1_260716T101530.mat", false);  % spaced subject
    threw = false;
    try
        m.prepareRecording(rtRec);
    catch ME2
        threw = strcmp(ME2.identifier, 'hw:Intan_RHX:UnrepresentableFilename');
    end
    assert_ok('Record run aborts on spaced target', threw);
    assert_ok('no filename.* sent when aborted', ~any(startsWith(m.Log, "set filename.")));

    % Preview (isTest) warns and continues instead of aborting
    m.resetLog();
    rtPrev = makeRuntime("C:/IntanData/Rat 1/Rat1_260716T101530.mat", true);
    m.prepareRecording(rtPrev);   % must not throw
    assert_ok('Preview does not abort on spaced target', true);
    assert_ok('Preview sends no filename.*', ~any(startsWith(m.Log, "set filename.")));
catch ME
    fprintf('  FAIL  space handling: %s\n', ME.message);
end

%% 8. Drain resynchronizes after a stray (rejected-command) response
try
    m = Intan_RHX_Mock(); m.connect();
    m.add_parameter('sampleratehertz', 30000);
    m.setReplies('get sampleratehertz', {'Return: SampleRateHertz 30000'});
    m.queueUnsolicited('Error: stray rejected-command response');
    v = m.get_parameter('sampleratehertz');
    assert_ok('get still parses after stray bytes drained', strcmp(v, '30000'));
catch ME
    fprintf('  FAIL  drain: %s\n', ME.message);
end

%% 9. trigger() gated on controller type
try
    % Plain recording controller: no execute is sent
    mr = Intan_RHX_Mock(REMOTE);
    mr.setReplies('get type', {'Return: Type ControllerRecordUSB3'});
    mr.connect(); mr.resetLog();
    pr = mr.add_parameter('trig', 0, isTrigger=true); pr.UserData.TriggerKey = 'f2';
    mr.trigger('trig'); mr.trigger('trig');
    assert_ok('recording controller: no trigger sent', ~any(startsWith(mr.Log, "execute")));

    % Stim/record controller: the pulse is issued with the requested key
    ms = Intan_RHX_Mock(REMOTE); ms.connect(); ms.resetLog();   % default StimRecord
    ps = ms.add_parameter('trig', 0, isTrigger=true); ps.UserData.TriggerKey = 'f3';
    ms.trigger('trig');
    assert_ok('stim/record controller: pulse issued', any(ms.Log == "execute manualstimtriggerpulse f3"));
catch ME
    fprintf('  FAIL  trigger gating: %s\n', ME.message);
end

%% 10. mode reads are throttled: 50 reads inside the TTL query once
try
    m = Intan_RHX_Mock(); m.connect(); m.resetLog();
    m.ModePollInterval = 0.25;   % real throttle window
    m.forceModeExpiry();
    for k = 1:50, m.mode; end
    assert_ok('50 mode reads -> exactly one get runmode', m.logCount('get runmode') == 1);
catch ME
    fprintf('  FAIL  throttle: %s\n', ME.message);
end

%% 11. DeviceState.Stop maps to 'set runmode stop' (never 'run')
try
    m = Intan_RHX_Mock(); m.connect(); m.resetLog();
    m.mode = hw.DeviceState.Stop;
    assert_ok('Stop -> set runmode stop', any(m.Log == "set runmode stop"));
    assert_ok('Stop never sends set runmode run', ~any(m.Log == "set runmode run"));
catch ME
    fprintf('  FAIL  Stop mapping: %s\n', ME.message);
end

%% 12. A garbled runmode reply returns the cache, never Idle
try
    m = Intan_RHX_Mock(); m.connect();
    m.setReplies('get runmode', {'Return: RunMode Record'});
    m.mode = hw.DeviceState.Record;      % cache -> Record
    m.ModePollInterval = 0;              % always query
    m.forceModeExpiry();
    m.setReplies('get runmode', {'Return: RunMode Gibberish'});
    mo = m.mode;
    assert_ok('garbled reply -> cached mode, not Idle', mo == hw.DeviceState.Record && mo ~= hw.DeviceState.Idle);
catch ME
    fprintf('  FAIL  garbled mode: %s\n', ME.message);
end

%% 13. Settings file loads once at connect, not again when unchanged
try
    m = Intan_RHX_Mock(REMOTE);
    m.SettingsFile = 'C:/cfg/rhx.xml';
    m.connect();
    assert_ok('settings file loaded at connect', any(m.Log == "execute loadsettingsfile C:/cfg/rhx.xml"));
    m.resetLog();
    m.RecordingRootDir = 'C:/IntanData';
    rt = makeRuntime("C:/IntanData/Rat1/Rat1_260716T101530.mat", false);
    m.prepareRecording(rt);
    assert_ok('unchanged settings file not reloaded', ~any(startsWith(m.Log, "execute loadsettingsfile")));
catch ME
    fprintf('  FAIL  settings file: %s\n', ME.message);
end

fprintf('\n=== Done ===\n\n');
