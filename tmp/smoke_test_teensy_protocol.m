% smoke_test_teensy_protocol.m
% Protocol round-trip tests for hw.Teensy — no hardware required.
%
% Targets the failure mode that is otherwise SILENT: epsych.Protocol rebuilds
% interfaces through a hard-coded switch whose `otherwise` branch returns
% hw.Software(). A backend missing from that switch saves fine and reloads as a
% software stub with no error at all, and the first sign of trouble is a session
% that will not start. These tests assert the reloaded interface is really a
% hw.Teensy and that its construction options survived.
%
% Run headless:
%   matlab -batch "run('tmp/smoke_test_teensy_protocol.m')"

fprintf('\n=== hw.Teensy Protocol Round-Trip Test ===\n\n');
results = {};

scratch = tempname;
mkdir(scratch);
cleanupScratch = onCleanup(@() rmdir(scratch, 's'));
protocolFile = fullfile(scratch, 'teensy_roundtrip.eprot');

%% 1. Build a protocol carrying a Teensy interface
try
    prot = epsych.Protocol(Name = 'TeensyRoundTrip');

    iface = hw.Teensy('COM7', Connect = false, BaudRate = 115200, ...
        AutoDetect = true, DeviceSerial = 'ABC123');
    m = hw.Module(iface, 'Teensy', 'Teensy', uint8(1));
    m.Fs = 10000;

    m.add_parameter('x_NewTrial_1', 0,      Type = 'Boolean', Access = 'Any', isTrigger = true);
    m.add_parameter('x_ResetTrig_1', 0,     Type = 'Boolean', Access = 'Any', isTrigger = true);
    m.add_parameter('x_TrialComplete_1', 0, Type = 'Boolean', Access = 'Read');
    m.add_parameter('RespCode', 0,          Type = 'Integer', Access = 'Read');
    m.add_parameter('RewardDur', [25 50 75], Type = 'Float', Access = 'Any', Unit = 'ms');
    iface.setModules(m);

    prot.addInterface(iface);
    % A new protocol already carries an hw.Software interface, so look the
    % Teensy up by type rather than assuming it landed at a particular index.
    results(end+1,:) = check('Protocol accepts a Teensy interface', ...
        ~isempty(prot.findInterface('Teensy')));
    results(end+1,:) = check('Software interface is still present', ...
        ~isempty(prot.findInterface('Software')));
catch ME
    results(end+1,:) = check(['Build protocol: ' ME.message], false);
end

%% 2. Save and reload
try
    prot.save(protocolFile);
    results(end+1,:) = check('Protocol saved', isfile(protocolFile));

    reloaded = epsych.Protocol.load(protocolFile);
    results(end+1,:) = check('Protocol reloaded', ~isempty(reloaded));

    back = reloaded.findInterface('Teensy');

    % The load-bearing assertion. Without a 'Teensy' case in
    % createInterfaceFromStruct_ the interface comes back as hw.Software, its
    % Type no longer matches, findInterface returns empty, and nothing warns.
    results(end+1,:) = check('Reloaded interface is found by type', ~isempty(back));
    results(end+1,:) = check('Reloaded interface is a hw.Teensy', isa(back, 'hw.Teensy'));
    results(end+1,:) = check('Reloaded interface is NOT a software stub', ...
        ~isa(back, 'hw.Software'));
catch ME
    results(end+1,:) = check(['Save/reload: ' ME.message], false);
end

%% 3. Construction options survived the round trip
try
    back = reloaded.findInterface('Teensy');

    % Port is a char serial name here, not Intan's numeric TCP port. Coercing
    % it with double() would silently store [67 79 77 55].
    results(end+1,:) = check('Port survived as a char name', ...
        ischar(back.Port) && strcmp(back.Port, 'COM7'));
    results(end+1,:) = check('BaudRate survived',     back.BaudRate == 115200);
    results(end+1,:) = check('AutoDetect survived',   back.AutoDetect == true);
    results(end+1,:) = check('DeviceSerial survived', strcmp(back.DeviceSerial, 'ABC123'));
    results(end+1,:) = check('Reloaded interface is offline', ~back.IsConnected);
catch ME
    results(end+1,:) = check(['Options round-trip: ' ME.message], false);
end

%% 4. Modules and parameter metadata survived
try
    back = reloaded.findInterface('Teensy');
    results(end+1,:) = check('One module survived', numel(back.Module) == 1);
    results(end+1,:) = check('Module Fs survived',  back.Module(1).Fs == 10000);
    results(end+1,:) = check('All five parameters survived', ...
        numel(back.Module(1).Parameters) == 5);

    newTrial = back.find_parameter('x_NewTrial_1', includeInvisible = true);
    results(end+1,:) = check('x_NewTrial_1 is still a trigger', newTrial.isTrigger);
    results(end+1,:) = check('x_NewTrial_1 Access is still Any', strcmp(newTrial.Access, 'Any'));

    complete = back.find_parameter('x_TrialComplete_1', includeInvisible = true);
    results(end+1,:) = check('x_TrialComplete_1 Access is still Read', ...
        strcmp(complete.Access, 'Read'));

    reward = back.find_parameter('RewardDur');
    results(end+1,:) = check('RewardDur kept its three trial levels', ...
        numel(reward.Values) == 3);
    results(end+1,:) = check('RewardDur kept its unit', strcmp(reward.Unit, 'ms'));
catch ME
    results(end+1,:) = check(['Module round-trip: ' ME.message], false);
end

%% 5. The reloaded protocol compiles into a trial table
try
    reloaded.compile();
    results(end+1,:) = check('Reloaded protocol compiles', reloaded.COMPILED.ntrials == 3);
    % Read-only and trigger parameters must not become trial columns.
    wp = reloaded.COMPILED.writeparams;
    results(end+1,:) = check('RewardDur is a write column', any(strcmp(wp, 'RewardDur')));
    results(end+1,:) = check('Read-only parameters are not write columns', ...
        ~any(strcmp(wp, 'x_TrialComplete_1')) && ~any(strcmp(wp, 'RespCode')));
    % Triggers DO appear as compiled columns — compile_internal filters only on
    % Visible and Access, not isTrigger. What keeps them from being written every
    % trial is UpdateEveryTrial=false, which hw.Parameter.set.isTrigger sets
    % automatically and which dispatchNextTrial filters on. Assert that, since it
    % is the property that actually protects them.
    trigs = [reloaded.findInterface('Teensy').find_parameter( ...
        {'x_NewTrial_1', 'x_ResetTrig_1'}, includeInvisible = true)];
    results(end+1,:) = check('Triggers survive as triggers', all([trigs.isTrigger]));
    results(end+1,:) = check('Triggers are excluded from per-trial dispatch', ...
        ~any([trigs.UpdateEveryTrial]));
    results(end+1,:) = check('Trigger columns add no trial conditions', ...
        reloaded.COMPILED.ntrials == 3);
catch ME
    results(end+1,:) = check(['Compile: ' ME.message], false);
end

%% 6. ProtocolDesigner registry knows about the backend
% getAvailableInterfaceSpecs lives in the @ProtocolDesigner/private folder, so
% it is unreachable from a script. Assert against the source instead: this
% registry is a hard-coded list with no reflection, and omitting a backend from
% it is exactly why hw.VlcRecorder never appears in the designer.
try
    registryFile = fullfile(fileparts(which('epsych.ProtocolDesigner')), ...
        'private', 'getAvailableInterfaceSpecs.m');
    src = fileread(registryFile);
    results(end+1,:) = check('Designer registry lists a Teensy spec', ...
        contains(src, 'localSerializedTeensySpec_()'));
    results(end+1,:) = check('Designer registry calls hw.Teensy.getCreationSpec', ...
        contains(src, 'hw.Teensy.getCreationSpec'));
    % The designer must never touch hardware while editing a protocol.
    results(end+1,:) = check('Designer factory constructs with Connect = false', ...
        contains(src, 'hw.Teensy(port, Connect = false'));

    editFile = fullfile(fileparts(which('epsych.ProtocolDesigner')), ...
        'private', 'getInterfaceEditState.m');
    results(end+1,:) = check('Designer can edit Teensy options', ...
        contains(fileread(editFile), "case 'Teensy'"));
catch ME
    results(end+1,:) = check(['Designer registry: ' ME.message], false);
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
    error('smoke_test_teensy_protocol:Failed', '%d test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end
