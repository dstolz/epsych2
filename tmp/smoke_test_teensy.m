% smoke_test_teensy.m
% Offline smoke tests for hw.Teensy — no hardware required.
%
% Drives the backend against tmp/Teensy_Mock, which simulates the EPsychTeensy
% firmware in process. Because the mock overrides only the byte-level transport
% seam, every protocol path exercised here is the same code a real board runs.
%
% Run headless:
%   matlab -batch "run('tmp/smoke_test_teensy.m')"

fprintf('\n=== hw.Teensy Smoke Test ===\n\n');
results = {};

%% 1. Offline construction
try
    iface = hw.Teensy('COM99', Connect = false);
    results(end+1,:) = check('Offline construction',        true);
    results(end+1,:) = check('Type == "Teensy"',            iface.Type == "Teensy");
    results(end+1,:) = check('IsConnected == false',        ~iface.IsConnected);
    results(end+1,:) = check('Port preserved',              strcmp(iface.Port, 'COM99'));
    results(end+1,:) = check('Module is empty',             isempty(iface.Module));
    results(end+1,:) = check('mode does not query offline', iface.mode == hw.DeviceState.Idle);
catch ME
    results(end+1,:) = check(['Offline construction: ' ME.message], false);
end

%% 2. getCreationSpec
try
    spec = hw.Teensy.getCreationSpec();
    optNames = {spec.options.name};
    results(end+1,:) = check('getCreationSpec returns hw.InterfaceSpec', isa(spec, 'hw.InterfaceSpec'));
    results(end+1,:) = check('spec.type == Teensy',      strcmp(char(spec.type), 'Teensy'));
    results(end+1,:) = check('spec has port option',     any(strcmp(optNames, 'port')));
    results(end+1,:) = check('spec has autoDetect',      any(strcmp(optNames, 'autoDetect')));
    results(end+1,:) = check('spec has deviceSerial',    any(strcmp(optNames, 'deviceSerial')));
    results(end+1,:) = check('spec has baudRate',        any(strcmp(optNames, 'baudRate')));
    adOpt = spec.options(strcmp(optNames, 'autoDetect'));
    results(end+1,:) = check('autoDetect renders as a checkbox', strcmp(adOpt.controlType, 'checkbox'));
    results(end+1,:) = check('spec.createFcn is callable', isa(spec.createFcn, 'function_handle'));
catch ME
    results(end+1,:) = check(['getCreationSpec: ' ME.message], false);
end

%% 3. Offline parameter I/O must be benign, not fatal
try
    iface = hw.Teensy('COM99', Connect = false);
    m = hw.Module(iface, 'Teensy', 'Teensy', uint8(1));
    m.add_parameter('RewardDur', 50, Type = 'Float', Access = 'Any');
    iface.setModules(m);

    results(end+1,:) = check('setModules while offline', numel(iface.Module) == 1);
    results(end+1,:) = check('set_parameter offline returns true', ...
        iface.set_parameter('RewardDur', 75));

    % The runtime writes through hw.Parameter.set.Value, which stores the value
    % locally and *then* calls set_parameter. A backend's set_parameter must not
    % store it again (hw.Software makes the same point), so the offline read-back
    % has to be driven the way the runtime drives it.
    P = iface.find_parameter('RewardDur');
    P.Value = 75;
    results(end+1,:) = check('get_parameter offline serves the local cache', ...
        isequal(iface.get_parameter('RewardDur'), 75));
    results(end+1,:) = check('trigger offline returns a double', ...
        isa(iface.trigger('RewardDur'), 'double'));
catch ME
    results(end+1,:) = check(['Offline parameter I/O: ' ME.message], false);
end

%% 4. Connect and discover through the simulated firmware
% Typed empty, not []: assigning a field to [] would silently turn `mock` into
% a struct and every later section would fail with a confusing message.
mock = hw.Teensy.empty;
try
    mock = Teensy_Mock();
    results(end+1,:) = check('Mock connects',                mock.IsConnected);
    results(end+1,:) = check('Handshake read the board type', contains(mock.BoardType, 'Teensy4.1'));
    results(end+1,:) = check('Handshake read the firmware',   strcmp(mock.FirmwareVersion, '1.0.0'));
    results(end+1,:) = check('Protocol version matches',      mock.ProtocolVersion == mock.PROTOCOL_VERSION);
    results(end+1,:) = check('One module was created',        numel(mock.Module) == 1);
    results(end+1,:) = check('Module Fs is the tick rate',    mock.Module(1).Fs == mock.TickHz);

    P = mock.all_parameters(includeInvisible = true);
    results(end+1,:) = check('Descriptor produced parameters', numel(P) == 12);

    % Assert the batching *mechanism*, not a wall-clock threshold: three
    % MATLAB-side reads can easily take longer than the 5 ms production TTL,
    % which would expire the cache mid-test for reasons that say nothing about
    % the code. Sections below invalidate explicitly when they need a fresh read.
    mock.SnapshotInterval = 5;
catch ME
    results(end+1,:) = check(['Connect/discover: ' ME.message], false);
end

%% 5. The three names epsych.Runtime requires must resolve correctly
try
    for nm = {'x_NewTrial_1', 'x_ResetTrig_1', 'x_TrialComplete_1'}
        p = mock.find_parameter(nm{1}, includeInvisible = true, silenceParameterNotFound = true);
        results(end+1,:) = check(sprintf('%s exists', nm{1}), ~isempty(p));
    end

    newTrial = mock.find_parameter('x_NewTrial_1', includeInvisible = true);
    results(end+1,:) = check('x_NewTrial_1 is a trigger',   newTrial.isTrigger);
    % A 'Write' trigger is invisible to Runtime.all_parameters and would abort
    % the session with epsych:RunExpt:MissingTrigger.
    results(end+1,:) = check('x_NewTrial_1 Access is Any',  strcmp(newTrial.Access, 'Any'));
    results(end+1,:) = check('trigger clears UpdateEveryTrial', ~newTrial.UpdateEveryTrial);

    complete = mock.find_parameter('x_TrialComplete_1', includeInvisible = true);
    results(end+1,:) = check('x_TrialComplete_1 is Read',   strcmp(complete.Access, 'Read'));
    results(end+1,:) = check('x_TrialComplete_1 is Boolean', strcmp(complete.Type, 'Boolean'));

    hidden = mock.find_parameter('_TrigState~1', includeInvisible = true);
    results(end+1,:) = check('_TrigState~1 is hidden', ~hidden.Visible);
catch ME
    results(end+1,:) = check(['Required parameter names: ' ME.message], false);
end

%% 6. Snapshot cache — N reads must cost one SNAP
try
    mock.Log = {};
    mock.snapshotInvalidate();
    v1 = mock.get_parameter('RewardDur');
    v2 = mock.get_parameter('CueLevel');
    v3 = mock.get_parameter('TrialType');
    nSnap = sum(strcmp(mock.Log, 'SNAP'));
    results(end+1,:) = check('Three reads issue one SNAP', nSnap == 1);
    results(end+1,:) = check('Snapshot returned real values', ...
        isequal(v1, 50) && isequal(v2, 60) && isequal(v3, 0));
catch ME
    results(end+1,:) = check(['Snapshot cache: ' ME.message], false);
end

%% 7. get_parameter must preserve the requested order
try
    mock.snapshotInvalidate();
    vals = mock.get_parameter({'CueLevel', 'RewardDur'});
    results(end+1,:) = check('Multi-read returns a cell',    iscell(vals) && numel(vals) == 2);
    results(end+1,:) = check('Requested order is preserved', ...
        isequal(vals{1}, 60) && isequal(vals{2}, 50));
catch ME
    results(end+1,:) = check(['Read order: ' ME.message], false);
end

%% 8. Write coalescing — k writes must flush as one SETM at the trigger
try
    mock.Log = {};
    mock.set_parameter('RewardDur', 120);
    mock.set_parameter('CueLevel', 45);
    mock.set_parameter('TrialType', 2);
    results(end+1,:) = check('Writes are buffered, not sent', ...
        ~any(startsWith(mock.Log, 'SET')));

    t = mock.trigger('x_NewTrial_1');
    setmCount = sum(startsWith(mock.Log, 'SETM'));
    results(end+1,:) = check('Trigger flushes one SETM', setmCount == 1);
    results(end+1,:) = check('SETM precedes TRG', ...
        find(startsWith(mock.Log, 'SETM'), 1) < find(startsWith(mock.Log, 'TRG'), 1));
    results(end+1,:) = check('trigger returns a double (lastUpdated is double)', ...
        isa(t, 'double') && isscalar(t));

    mock.snapshotInvalidate();
    results(end+1,:) = check('Coalesced writes actually landed', ...
        isequal(mock.get_parameter('RewardDur'), 120));
catch ME
    results(end+1,:) = check(['Write coalescing: ' ME.message], false);
end

%% 9. A read also flushes pending writes
try
    mock.Log = {};
    mock.set_parameter('CueLevel', 33);
    mock.snapshotInvalidate();
    v = mock.get_parameter('CueLevel');
    results(end+1,:) = check('Read flushes pending writes first', ...
        any(startsWith(mock.Log, 'SETM')));
    results(end+1,:) = check('Read sees the flushed value', isequal(v, 33));
catch ME
    results(end+1,:) = check(['Read-triggered flush: ' ME.message], false);
end

%% 10. Trial handshake: reset -> write -> trigger -> poll -> complete
try
    mock.trigger('x_ResetTrig_1');
    mock.snapshotInvalidate();
    results(end+1,:) = check('ResetTrig clears TrialComplete', ...
        isequal(mock.get_parameter('x_TrialComplete_1'), 0));

    mock.trigger('x_NewTrial_1');
    mock.snapshotInvalidate();
    results(end+1,:) = check('NewTrial raises InTrial', ...
        isequal(mock.get_parameter('InTrial'), 1));

    mock.completeTrial(RespCode = 33, RespLatency = 187);
    mock.snapshotInvalidate();
    results(end+1,:) = check('Board raises TrialComplete', ...
        isequal(mock.get_parameter('x_TrialComplete_1'), 1));
    results(end+1,:) = check('RespCode reads back', ...
        isequal(mock.get_parameter('RespCode'), 33));

    % 33 = bits 1 and 6 = Hit + Reward, the encoding the firmware must produce.
    decoded = epsych.BitMask.Mask2Bits(uint32(33));
    results(end+1,:) = check('RespCode 33 decodes as Hit+Reward', ...
        decoded(1) && decoded(6) && ~decoded(2));
catch ME
    results(end+1,:) = check(['Trial handshake: ' ME.message], false);
end

%% 11. mode is cached, not re-queried every read
try
    mock.mode = hw.DeviceState.Record;
    mock.Log = {};
    for i = 1:20
        m = mock.mode;
    end
    results(end+1,:) = check('mode reads are served from cache', ...
        ~any(strcmp(mock.Log, 'MODE?')));
    results(end+1,:) = check('mode round-trips as Record', m == hw.DeviceState.Record);
catch ME
    results(end+1,:) = check(['mode cache: ' ME.message], false);
end

%% 12. Event queue
try
    mock.pushEvent('Lick_1', 1);
    mock.pushEvent('Lick_1', 0);
    E = mock.drainEvents();
    results(end+1,:) = check('drainEvents returns Nx3',   size(E, 1) == 2 && size(E, 2) == 3);
    results(end+1,:) = check('Event timestamps ascend',   E(2,1) > E(1,1));
    results(end+1,:) = check('Queue is emptied by a drain', isempty(mock.drainEvents()));
catch ME
    results(end+1,:) = check(['Event queue: ' ME.message], false);
end

%% 13. readHardwareParameters is idempotent under merge
try
    before = numel(mock.Module(1).Parameters);
    [tf, msg] = mock.readHardwareParameters(mock.Module(1));
    after = numel(mock.Module(1).Parameters);
    results(end+1,:) = check('readHardwareParameters succeeds', tf);
    results(end+1,:) = check('merge mode is idempotent', before == after);
    results(end+1,:) = check('readHardwareParameters reports a message', ~isempty(msg));
catch ME
    results(end+1,:) = check(['readHardwareParameters: ' ME.message], false);
end

%% 14. selfTest never throws
try
    r = mock.selfTest();
    results(end+1,:) = check('selfTest returns results', ~isempty(r));
    results(end+1,:) = check('selfTest statuses are valid', ...
        all(ismember(string({r.status}), ["pass","fail","warn","info","skip"])));
catch ME
    results(end+1,:) = check(['selfTest: ' ME.message], false);
end

%% 15. Disconnect
try
    mock.disconnect();
    results(end+1,:) = check('disconnect clears IsConnected', ~mock.IsConnected);
    results(end+1,:) = check('reads after disconnect do not throw', ...
        ~isempty(mock.get_parameter('RewardDur')) || true);
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
fprintf('\n%d passed, %d failed, %d total\n\n', sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_teensy:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end
