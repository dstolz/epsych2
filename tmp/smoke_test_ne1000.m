% smoke_test_ne1000.m
% Offline smoke tests for hw.NE1000 — no pump required.
%
% Drives the backend against tmp/NE1000_Mock, which simulates the NE-1000's
% Basic-mode RS-232 protocol in process. Because the mock overrides only the
% transport-seam methods, every protocol path exercised here is the same code a
% real pump runs: the Basic-mode framing and parser, the power-up alarm
% acknowledgment, the RAT units fallback, the shared DIS cache, and the
% stop-on-teardown safety path. Also checks the pure helpers and the
% designer/serialization registry wiring.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_ne1000.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('hw.NE1000', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== hw.NE1000 Smoke Test ===\n\n');
results = {};

%% 1. Offline construction
try
    iface = hw.NE1000('COM4', Connect = false, Address = 2, ...
        SyringeDiameter = 21.59, RateUnits = 'MM');
    results(end+1,:) = check('Offline construction',   true);
    results(end+1,:) = check('Type == "NE1000"',       iface.Type == "NE1000");
    results(end+1,:) = check('IsConnected == false',   ~iface.IsConnected);
    results(end+1,:) = check('Port preserved',         strcmp(iface.Port, 'COM4'));
    results(end+1,:) = check('Address preserved',      iface.Address == 2);
    results(end+1,:) = check('Diameter preserved',     iface.SyringeDiameter == 21.59);
    results(end+1,:) = check('RateUnits preserved',    strcmp(iface.RateUnits, 'MM'));
    results(end+1,:) = check('Module is empty',        isempty(iface.Module));
    results(end+1,:) = check('mode is inert offline',  iface.mode == hw.DeviceState.Idle);

    m = hw.Module(iface, 'NE1000', 'Pump', uint8(1));
    m.add_parameter('Rate', 1, Type = 'Float', Access = 'Any');
    iface.setModules(m);
    results(end+1,:) = check('setModules while offline', isscalar(iface.Module));
    results(end+1,:) = check('set_parameter offline returns true', ...
        iface.set_parameter('Rate', 0.5));

    % The runtime writes through hw.Parameter.set.Value, which stores the value
    % locally and then calls set_parameter. Offline reads are driven the same
    % way, because add_parameter seeds Values (design-time levels), not Value.
    P = iface.find_parameter('Rate');
    P.Value = 0.5;
    results(end+1,:) = check('get_parameter offline serves the local cache', ...
        isequal(iface.get_parameter('Rate'), 0.5));
    results(end+1,:) = check('trigger offline returns a double', ...
        isa(iface.trigger('Rate'), 'double'));
    results(end+1,:) = check('Offline interface is still disconnected', ~iface.IsConnected);
catch ME
    results(end+1,:) = check(['Offline construction: ' ME.message], false);
end

%% 2. getCreationSpec
try
    spec = hw.NE1000.getCreationSpec();
    optNames = {spec.options.name};
    results(end+1,:) = check('getCreationSpec returns hw.InterfaceSpec', isa(spec, 'hw.InterfaceSpec'));
    % getInterfaceEditState looks the spec up by the interface's Type and errors
    % outright when the lookup fails, so this must match char(hw.NE1000.Type).
    results(end+1,:) = check('spec.type == char(hw.NE1000.Type)', ...
        strcmp(char(spec.type), char(hw.NE1000.Type)));
    wanted = {'port', 'autoDetect', 'address', 'baudRate', 'syringeDiameter', ...
        'rateUnits', 'ttlTrigger'};
    results(end+1,:) = check('spec has exactly the seven options', ...
        numel(spec.options) == 7 && all(ismember(wanted, optNames)));
    % The trigger MODE is programmatic only: offering it here would put it in
    % the designer's interface dialog.
    results(end+1,:) = check('spec does not offer the trigger mode', ...
        ~any(contains(lower(optNames), 'mode')));
    results(end+1,:) = check('spec.createFcn is callable', isa(spec.createFcn, 'function_handle'));
catch ME
    results(end+1,:) = check(['getCreationSpec: ' ME.message], false);
end

%% 3. Pure helpers: response parser and value formatting
try
    R = hw.NE1000.parseResponse_([char(2) '0S' char(3)]);
    results(end+1,:) = check('parse: stopped status', R.ok && R.status == 'S' && isempty(R.data));

    R = hw.NE1000.parseResponse_([char(2) '10I10.0MH' char(3)]);
    results(end+1,:) = check('parse: infusing with data, 2-digit address', ...
        R.ok && R.status == 'I' && strcmp(R.data, '10.0MH'));

    R = hw.NE1000.parseResponse_([char(2) '0A?R' char(3)]);
    results(end+1,:) = check('parse: reset alarm', R.ok && strcmp(R.alarm, 'R'));

    R = hw.NE1000.parseResponse_([char(2) '0S?OOR' char(3)]);
    results(end+1,:) = check('parse: out-of-range error', R.ok && strcmp(R.err, 'OOR'));

    R = hw.NE1000.parseResponse_([char(2) '0S?' char(3)]);
    results(end+1,:) = check('parse: bare ? error', R.ok && ~isempty(R.err));

    R = hw.NE1000.parseResponse_('');
    results(end+1,:) = check('parse: empty is not ok', ~R.ok);

    R = hw.NE1000.parseResponse_('garbage');
    results(end+1,:) = check('parse: garbage is not ok', ~R.ok);

    % The pump's grammar allows at most 4 digits plus one decimal point.
    okFmt = @(s) numel(regexprep(s, '\.', '')) <= 4 && sum(s == '.') <= 1;
    vals = [0.73 1.5 10.25 199.9 1699 0.004];
    allOk = true;
    for v = vals
        s = hw.NE1000.formatFloat_(v);
        allOk = allOk && okFmt(s) && abs(str2double(s) - v) <= max(0.005 * v, 0.0005);
    end
    results(end+1,:) = check('formatFloat_ stays within 4 digits and close', allOk);

    results(end+1,:) = check('directionCode_ maps friendly names', ...
        strcmp(hw.NE1000.directionCode_('Infuse'), 'INF') && ...
        strcmp(hw.NE1000.directionCode_('withdraw'), 'WDR') && ...
        strcmp(hw.NE1000.directionCode_(0), 'INF') && ...
        strcmp(hw.NE1000.directionCode_(1), 'WDR') && ...
        isempty(hw.NE1000.directionCode_('sideways')));
catch ME
    results(end+1,:) = check(['Pure helpers: ' ME.message], false);
end

%% 4. Connect handshake (mock)
mock = hw.NE1000.empty;
try
    mock = NE1000_Mock(SyringeDiameter = 21.59);
    results(end+1,:) = check('Mock connects', mock.IsConnected);
    results(end+1,:) = check('Safe-mode escape packet sent first', ...
        ~isempty(mock.RawLog) && isequal(mock.RawLog{1}(1:2), uint8([2 8])));
    % The simulated pump answered the first VER with its power-up reset alarm;
    % connect must have acknowledged it and retried.
    results(end+1,:) = check('Power-up alarm was acknowledged', strcmp(mock.LastAlarm, 'R'));
    results(end+1,:) = check('FirmwareVersion captured', ...
        strcmp(mock.FirmwareVersion, 'NE1000V3.928'));
    results(end+1,:) = check('Connect stopped the pump (STP)', ...
        any(contains(mock.Log, 'STP')));
    results(end+1,:) = check('Connect pushed the syringe diameter', ...
        abs(mock.SimDiameter - 21.59) < 0.01);
    results(end+1,:) = check('mode is Standby after connect', ...
        mock.mode == hw.DeviceState.Standby);

    P = mock.all_parameters(includeInvisible = true, includeTriggers = true);
    names = {P.Name};
    wanted = {'Rate', 'Volume', 'Direction', 'Diameter', 'VolumeInfused', ...
        'VolumeWithdrawn', 'Status', 'TTLTrigger', 'Start', 'Stop', 'ClearVolume'};
    results(end+1,:) = check('All eleven parameters exist', all(ismember(wanted, names)));

    % The DATA sweep (Visible && ~isTrigger && Access ~= 'Write').
    D = mock.all_parameters(Access = 'Read');
    results(end+1,:) = check('DATA sweep = Rate, Volume, VolumeInfused, VolumeWithdrawn', ...
        isempty(setxor({D.Name}, {'Rate', 'Volume', 'VolumeInfused', 'VolumeWithdrawn'})));

    % Reconnecting must not duplicate parameters (merge semantics).
    mock.disconnect();
    mock.connect();
    P2 = mock.all_parameters(includeInvisible = true, includeTriggers = true);
    results(end+1,:) = check('Reconnect does not duplicate parameters', ...
        numel(P2) == numel(P));
catch ME
    results(end+1,:) = check(['Connect handshake: ' ME.message], false);
end

%% 5. Writes
try
    results(end+1,:) = check('set Rate while stopped', ...
        mock.set_parameter('Rate', 0.5) && abs(mock.SimRate - 0.5) < 1e-9);
    results(end+1,:) = check('Rate write carried the units', ...
        strcmp(mock.SimRateUnits, 'MH'));
    results(end+1,:) = check('set Volume', ...
        mock.set_parameter('Volume', 0.05) && abs(mock.SimVolume - 0.05) < 1e-9);
    results(end+1,:) = check('set Direction by name', ...
        mock.set_parameter('Direction', 'Withdraw') && strcmp(mock.SimDir, 'WDR'));
    mock.set_parameter('Direction', 'Infuse');
    results(end+1,:) = check('set Direction back to Infuse', strcmp(mock.SimDir, 'INF'));
    results(end+1,:) = check('bogus Direction is rejected', ...
        ~mock.set_parameter('Direction', 'sideways'));

    % Rate while pumping: the units form is rejected (?NA) and the write must
    % fall back to the bare value.
    mock.trigger('Start');
    nBefore = numel(mock.Log);
    ok = mock.set_parameter('Rate', 0.75);
    ratCmds = mock.Log(nBefore+1:end);
    results(end+1,:) = check('Rate mid-run falls back to unitless RAT', ...
        ok && abs(mock.SimRate - 0.75) < 1e-9 && numel(ratCmds) == 2);
    mock.trigger('Stop');
catch ME
    results(end+1,:) = check(['Writes: ' ME.message], false);
end

%% 6. Reads
try
    mock.SimRate = 2.5;
    results(end+1,:) = check('Rate reads live from the pump', ...
        abs(mock.get_parameter('Rate') - 2.5) < 1e-9);

    mock.SimInfused = 1.234;
    mock.SimWithdrawn = 0.111;
    nBefore = numel(mock.Log);
    vi = mock.get_parameter('VolumeInfused');
    vw = mock.get_parameter('VolumeWithdrawn');
    nDis = sum(contains(mock.Log(nBefore+1:end), 'DIS'));
    results(end+1,:) = check('DIS values parsed', ...
        abs(vi - 1.234) < 1e-9 && abs(vw - 0.111) < 1e-9);
    results(end+1,:) = check('One DIS served both volume reads (cache)', nDis == 1);

    results(end+1,:) = check('Status maps the prompt character', ...
        ismember(mock.get_parameter('Status', includeInvisible = true), ...
            {'Stopped', 'Paused'}));
    results(end+1,:) = check('Direction reads back as a friendly name', ...
        strcmp(mock.get_parameter('Direction', includeInvisible = true), 'Infuse'));
    results(end+1,:) = check('Diameter reads live', ...
        abs(mock.get_parameter('Diameter', includeInvisible = true) - 21.59) < 0.01);
catch ME
    results(end+1,:) = check(['Reads: ' ME.message], false);
end

%% 7. Triggers and mode safety
try
    mock.trigger('Start');
    results(end+1,:) = check('Start runs the pump', mock.SimStatus == 'I');
    mock.trigger('Stop');
    results(end+1,:) = check('Stop pauses the pump', any(mock.SimStatus == 'PS'));

    mock.SimInfused = 3;
    mock.SimWithdrawn = 2;
    mock.trigger('ClearVolume');
    results(end+1,:) = check('ClearVolume zeros both accumulators', ...
        mock.SimInfused == 0 && mock.SimWithdrawn == 0);

    % Leaving Record must stop the pump: the teardown safety path.
    mock.mode = hw.DeviceState.Record;
    mock.trigger('Start');
    mock.mode = hw.DeviceState.Idle;
    results(end+1,:) = check('mode -> Idle stops a running pump', ...
        any(mock.SimStatus == 'PS'));
catch ME
    results(end+1,:) = check(['Triggers: ' ME.message], false);
end

%% 7b. TTL Operational Trigger
try
    % The pump keeps its trigger setup in non-volatile memory (the mock powers
    % up as a keypad-configured foot switch), so connect must assert the host's
    % setting either way.
    off = NE1000_Mock();
    results(end+1,:) = check('Connect disables a keypad-enabled trigger', ...
        strcmp(off.SimTrigger, 'OF') && ~off.TTLTrigger);

    on = NE1000_Mock(TTLTrigger = true);
    results(end+1,:) = check('Connect asserts the requested trigger mode', ...
        strcmp(on.SimTrigger, 'LE'));
    results(end+1,:) = check('LE is the default mode', strcmp(on.TriggerMode, 'LE'));

    on.TriggerMode = 'ST';
    results(end+1,:) = check('Changing the mode while enabled rewrites TRG', ...
        strcmp(on.SimTrigger, 'ST'));

    on.TTLTrigger = false;
    results(end+1,:) = check('Disabling writes TRG OF', strcmp(on.SimTrigger, 'OF'));

    on.TriggerMode = 'T2';
    results(end+1,:) = check('Changing the mode while disabled writes nothing', ...
        strcmp(on.SimTrigger, 'OF'));

    % A mode the pump does not have is a programming error, not a log line.
    threw = false;
    try
        on.TriggerMode = 'ZZ';
    catch ME
        threw = strcmp(ME.identifier, 'hw:NE1000:BadTriggerMode');
    end
    results(end+1,:) = check('An unknown trigger mode is rejected', threw);
    results(end+1,:) = check('A rejected mode leaves the old one in place', ...
        strcmp(on.TriggerMode, 'T2'));

    % The parameter path: what a trial table, gui.components.Triggers, or the operator
    % panel writes.
    results(end+1,:) = check('set_parameter enables the trigger', ...
        on.set_parameter('TTLTrigger', true) && strcmp(on.SimTrigger, 'T2'));

    % A mode changed at the keypad is reported, not assumed.
    on.SimTrigger = 'FH';
    results(end+1,:) = check('get_parameter reads the trigger as enabled', ...
        isequal(on.get_parameter('TTLTrigger', includeInvisible = true), true));
    results(end+1,:) = check('A keypad mode change is read back', ...
        strcmp(on.TriggerMode, 'FH'));

    on.SimTrigger = 'OF';
    results(end+1,:) = check('get_parameter reads the trigger as disabled', ...
        isequal(on.get_parameter('TTLTrigger', includeInvisible = true), false) && ...
        ~on.TTLTrigger);

    % Offline the configuration is held, not written.
    cold = hw.NE1000('COM9', Connect = false, TTLTrigger = true, TriggerMode = 'RL');
    results(end+1,:) = check('Offline construction holds the trigger settings', ...
        cold.TTLTrigger && strcmp(cold.TriggerMode, 'RL'));

    off.disconnect();
    on.disconnect();
    delete(off);
    delete(on);
catch ME
    results(end+1,:) = check(['TTL trigger: ' ME.message], false);
end

%% 8. Protocol serialization round trip
try
    prot = epsych.Protocol();
    src = hw.NE1000('COM7', Connect = false, Address = 3, BaudRate = 9600, ...
        SyringeDiameter = 14.43, RateUnits = 'UM', TTLTrigger = true);
    m = hw.Module(src, 'NE1000', 'Pump', uint8(1));
    m.add_parameter('Rate', 1, Type = 'Float', Access = 'Any');
    src.setModules(m);
    prot.addInterface(src);

    S = prot.toStruct();
    prot2 = epsych.Protocol();
    prot2.fromStruct(S);

    restored = prot2.Interfaces(arrayfun(@(x) x.Type == "NE1000", prot2.Interfaces));
    results(end+1,:) = check('Round trip restores an hw.NE1000', ...
        isscalar(restored) && isa(restored, 'hw.NE1000'));
    results(end+1,:) = check('Round trip keeps Port',        strcmp(restored.Port, 'COM7'));
    results(end+1,:) = check('Round trip keeps Address',     restored.Address == 3);
    results(end+1,:) = check('Round trip keeps BaudRate',    restored.BaudRate == 9600);
    results(end+1,:) = check('Round trip keeps Diameter',    abs(restored.SyringeDiameter - 14.43) < 1e-9);
    results(end+1,:) = check('Round trip keeps RateUnits',   strcmp(restored.RateUnits, 'UM'));
    results(end+1,:) = check('Round trip keeps TTLTrigger',  restored.TTLTrigger);
    results(end+1,:) = check('Round trip keeps the module',  isscalar(restored.Module) ...
        && isscalar(restored.Module(1).Parameters));
catch ME
    results(end+1,:) = check(['Serialization: ' ME.message], false);
end

%% 8b. Degraded link: dropped replies and re-entrancy
% The failure this guards against was seen on a real pump: gui.components.SyringePump's
% 4 Hz poll fired inside the runtime's trial-end sweep, the two consumed each
% other's replies, and the reads that came back empty crashed the consumers a
% layer up.
try
    link = NE1000_Mock(RateUnits = 'MM');
    link.set_parameter('Rate', 2.5);

    % A query is idempotent, so one dropped reply is resent and the value
    % still arrives.
    link.DropReplies = 1;
    results(end+1,:) = check('A query survives one dropped reply', ...
        isequal(link.get_parameter('Rate'), 2.5));

    % Two drops exhaust the resend. The read must still be a number: the
    % trial-end sweep lands it straight in DATA.
    link.DropReplies = 2;
    results(end+1,:) = check('An unanswered read serves the last value, not []', ...
        isequal(link.get_parameter('Rate'), 2.5));

    % Status is the one volatile reading, so it says so instead.
    link.DropReplies = 2;
    results(end+1,:) = check('An unanswered Status reads Unknown', ...
        strcmp(link.get_parameter('Status', includeInvisible = true), 'Unknown'));

    % A command re-entered from inside a blocking read is dropped rather than
    % allowed to interleave: the outer read still gets its own reply, and the
    % nested one never reaches the wire.
    link.SimRate = 3.75;
    nBefore = numel(link.Log);
    link.ReentrantProbe = @() link.get_parameter('Status', includeInvisible = true);
    outer = link.get_parameter('Rate');
    results(end+1,:) = check('An interrupted read still gets its own reply', ...
        isequal(outer, 3.75));
    results(end+1,:) = check('The re-entrant command never reached the wire', ...
        numel(link.Log) - nBefore == 1);

    % A dropped read keeps the previous value even for Status: nobody asked
    % the pump anything, so nothing licenses reporting Unknown.
    link.SimStatus = 'I';
    link.get_parameter('Status', includeInvisible = true);
    link.ReentrantProbe = @() link.get_parameter('Status', includeInvisible = true);
    link.get_parameter('Rate');
    results(end+1,:) = check('A dropped read leaves the link usable', ...
        strcmp(link.get_parameter('Status', includeInvisible = true), 'Infusing'));

    link.disconnect();
catch ME
    results(end+1,:) = check(['Degraded link: ' ME.message], false);
end

%% 9. Disconnect
try
    nBefore = numel(mock.Log);
    mock.trigger('Start');
    mock.disconnect();
    results(end+1,:) = check('disconnect clears IsConnected', ~mock.IsConnected);
    results(end+1,:) = check('disconnect stopped the pump', ...
        any(contains(mock.Log(nBefore+1:end), 'STP')) && any(mock.SimStatus == 'PS'));
    mock.disconnect();
    results(end+1,:) = check('A second disconnect does not throw', true);
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
fprintf('\n%d passed, %d failed, %d total\n\n', ...
    sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_ne1000:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end
