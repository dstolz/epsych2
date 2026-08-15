% smoke_test_intan_rhx.m
% Offline smoke tests for hw.Intan_RHX — no hardware required.

fprintf('\n=== hw.Intan_RHX Smoke Test ===\n\n');
pass = 0; fail = 0;

function assert_ok(label, expr)
    if expr
        fprintf('  PASS  %s\n', label);
    else
        fprintf('  FAIL  %s\n', label);
    end
end

%% 1. Offline construction (default args)
try
    iface = hw.Intan_RHX('127.0.0.1', 5000, Connect=false);
    assert_ok('Offline construction (default host/port)', true);
    assert_ok('Type == "Intan_RHX"',    iface.Type == "Intan_RHX");
    assert_ok('IsConnected == false',   ~iface.IsConnected);
    assert_ok('Host == 127.0.0.1',      strcmp(iface.Host, '127.0.0.1'));
    assert_ok('Port == 5000',           iface.Port == 5000);
    assert_ok('mode == Idle',           iface.mode == hw.DeviceState.Idle);
    assert_ok('Module is empty',        isempty(iface.Module));
catch ME
    fprintf('  FAIL  Offline construction: %s\n', ME.message);
end

%% 2. getCreationSpec
try
    spec = hw.Intan_RHX.getCreationSpec();
    assert_ok('getCreationSpec returns hw.InterfaceSpec', isa(spec, 'hw.InterfaceSpec'));
    assert_ok('spec.type == Intan_RHX', strcmp(char(spec.type), 'Intan_RHX'));
    optNames = {spec.options.name};
    assert_ok('spec has host option',           any(strcmp(optNames, 'host')));
    assert_ok('spec has port option',           any(strcmp(optNames, 'port')));
    assert_ok('spec has settingsFile option',   any(strcmp(optNames, 'settingsFile')));
    assert_ok('spec has samplingRate option',   any(strcmp(optNames, 'samplingRate')));
    assert_ok('spec has controllerType option', any(strcmp(optNames, 'controllerType')));
    sfOpt = spec.options(strcmp(optNames, 'settingsFile'));
    assert_ok('settingsFile is a file picker', sfOpt.getFile);
catch ME
    fprintf('  FAIL  getCreationSpec: %s\n', ME.message);
end

%% 3. setModules while offline
try
    iface2 = hw.Intan_RHX('localhost', 5000, Connect=false);
    m = hw.Module(iface2, 'RHX', 'RHX', uint8(1));
    iface2.setModules(m);
    assert_ok('setModules offline', numel(iface2.Module) == 1);
catch ME
    fprintf('  FAIL  setModules offline: %s\n', ME.message);
end

%% 4. get_parameter / set_parameter offline (should return gracefully)
try
    iface3 = hw.Intan_RHX('localhost', 5000, Connect=false);
    m3 = hw.Module(iface3, 'RHX', 'RHX', uint8(1));
    iface3.setModules(m3);
    p = iface3.add_parameter('testparam', 0);
    val = iface3.get_parameter('testparam');
    assert_ok('get_parameter offline returns empty cell', isempty(val));
    res = iface3.set_parameter('testparam', 1);
    assert_ok('set_parameter offline returns true', all(res));
catch ME
    fprintf('  FAIL  get/set_parameter offline: %s\n', ME.message);
end

%% 5. trigger offline (should not error)
try
    iface4 = hw.Intan_RHX('localhost', 5000, Connect=false);
    m4 = hw.Module(iface4, 'RHX', 'RHX', uint8(1));
    iface4.setModules(m4);
    p4 = iface4.add_parameter('trig', 0, isTrigger=true);
    p4.UserData.TriggerKey = 'f1';
    t = iface4.trigger('trig');
    assert_ok('trigger offline returns datetime', isdatetime(t));
catch ME
    fprintf('  FAIL  trigger offline: %s\n', ME.message);
end

%% 6. Protocol serialization round-trip
try
    iface5 = hw.Intan_RHX('192.168.1.50', 5001, Connect=false);
    m5 = hw.Module(iface5, 'RHX', 'RHX', uint8(1));
    iface5.setModules(m5);
    iface5.add_parameter('amp.samplingrate', 20000);

    prot = epsych.Protocol();
    prot.addInterface(iface5);
    s = prot.toStruct();

    % Protocol() constructor adds a default Software interface; find Intan_RHX
    ifaceIdx = find(cellfun(@(d) strcmp(d.Type,'Intan_RHX'), s.InterfaceData), 1);
    ifaceS = s.InterfaceData{ifaceIdx};
    assert_ok('toStruct preserves Type',   strcmp(ifaceS.Type, 'Intan_RHX'));
    assert_ok('toStruct preserves Host',   strcmp(ifaceS.Host, '192.168.1.50'));
    assert_ok('toStruct preserves Port',   ifaceS.Port == 5001);

    % Round-trip deserialization
    prot2 = epsych.Protocol();
    prot2.fromStruct(s);
    intanIfaces = arrayfun(@(i) isa(prot2.Interfaces(i),'hw.Intan_RHX'), 1:numel(prot2.Interfaces));
    iface5r = prot2.Interfaces(find(intanIfaces,1));
    assert_ok('fromStruct reconstructs Intan_RHX', isa(iface5r, 'hw.Intan_RHX'));
    assert_ok('fromStruct Host round-trip',  strcmp(iface5r.Host, '192.168.1.50'));
    assert_ok('fromStruct Port round-trip',  iface5r.Port == 5001);
    assert_ok('fromStruct IsConnected=false', ~iface5r.IsConnected);
catch ME
    fprintf('  FAIL  Protocol round-trip: %s\n', ME.message);
end

%% 7. ProtocolDesigner spec availability (via public getAddableInterfaceSpecs)
try
    pd = epsych.ProtocolDesigner();
    specs = pd.getAddableInterfaceSpecs();
    types = cellfun(@(s) char(string(s.type)), specs, 'UniformOutput', false);
    assert_ok('Intan_RHX in getAddableInterfaceSpecs', any(strcmp(types, 'Intan_RHX')));
catch ME
    fprintf('  FAIL  ProtocolDesigner specs: %s\n', ME.message);
end

%% 8. getCreationSpec factory function creates offline interface
try
    pd3 = epsych.ProtocolDesigner();
    allSpecs = pd3.getAddableInterfaceSpecs();
    idx = find(cellfun(@(s) strcmp(char(string(s.type)),'Intan_RHX'), allSpecs), 1);
    spec8 = allSpecs{idx};
    opts8.host = '10.0.0.1';
    opts8.port = 5000;
    iface8 = spec8.createFcn(opts8);
    assert_ok('createFcn returns hw.Intan_RHX', isa(iface8, 'hw.Intan_RHX'));
    assert_ok('createFcn Host correct', strcmp(iface8.Host, '10.0.0.1'));
    assert_ok('createFcn IsConnected=false', ~iface8.IsConnected);
    assert_ok('createFcn tolerates missing new options', ...
        isempty(iface8.SettingsFile) && iface8.SamplingRate == 0 && isempty(iface8.ControllerType));

    % Full option set flows through the factory onto the interface
    opts8b = struct('host', '10.0.0.2', 'port', 5000, ...
        'settingsFile', 'C:/cfg/rhx.xml', 'samplingRate', 30000, ...
        'controllerType', 'ControllerRecordUSB3');
    iface8b = spec8.createFcn(opts8b);
    assert_ok('createFcn carries settingsFile',   strcmp(iface8b.SettingsFile, 'C:/cfg/rhx.xml'));
    assert_ok('createFcn carries samplingRate',   iface8b.SamplingRate == 30000);
    assert_ok('createFcn carries controllerType', strcmp(iface8b.ControllerType, 'ControllerRecordUSB3'));
catch ME
    fprintf('  FAIL  createFcn: %s\n', ME.message);
end

%% 8b. Protocol serialization round-trip of the new Intan fields
try
    p = epsych.Protocol();
    ifaceRT = hw.Intan_RHX('10.0.0.9', 5000, Connect=false, ...
        SettingsFile='C:/cfg/rhx.xml', SamplingRate=25000, ControllerType='ControllerStimRecord');
    p.addInterface(ifaceRT);
    s = p.toStruct();
    ifaceData = s.InterfaceData{end};
    assert_ok('toStruct serializes SettingsFile',   strcmp(ifaceData.SettingsFile, 'C:/cfg/rhx.xml'));
    assert_ok('toStruct serializes SamplingRate',   ifaceData.SamplingRate == 25000);
    assert_ok('toStruct serializes ControllerType', strcmp(ifaceData.ControllerType, 'ControllerStimRecord'));

    p2 = epsych.Protocol();
    p2.fromStruct(s);
    ir = p2.Interfaces(end);
    assert_ok('fromStruct restores SettingsFile',   strcmp(ir.SettingsFile, 'C:/cfg/rhx.xml'));
    assert_ok('fromStruct restores SamplingRate',   ir.SamplingRate == 25000);
    assert_ok('fromStruct restores ControllerType', strcmp(ir.ControllerType, 'ControllerStimRecord'));
catch ME
    fprintf('  FAIL  serialization round-trip: %s\n', ME.message);
end

%% 9. RecordingRootDir / SettingsFile setters: normalize slashes, reject spaces
try
    iface9 = hw.Intan_RHX('localhost', 5000, Connect=false);
    iface9.RecordingRootDir = 'C:\Data\Intan\';
    assert_ok('RecordingRootDir normalizes slashes/trailing', strcmp(iface9.RecordingRootDir, 'C:/Data/Intan'));
    iface9.SettingsFile = 'C:\cfg\rhx.xml';
    assert_ok('SettingsFile normalizes slashes', strcmp(iface9.SettingsFile, 'C:/cfg/rhx.xml'));

    threwRoot = false;
    try
        iface9.RecordingRootDir = 'C:\Data\Rat 1';
    catch ME
        threwRoot = strcmp(ME.identifier, 'hw:Intan_RHX:PathHasSpaces');
    end
    assert_ok('RecordingRootDir rejects spaces', threwRoot);

    threwSet = false;
    try
        iface9.SettingsFile = 'C:\my cfg\rhx.xml';
    catch ME
        threwSet = strcmp(ME.identifier, 'hw:Intan_RHX:PathHasSpaces');
    end
    assert_ok('SettingsFile rejects spaces', threwSet);
catch ME
    fprintf('  FAIL  path setters: %s\n', ME.message);
end

%% 10. prepareRecording is a no-op while offline (no throw, no state change)
try
    iface10 = hw.Intan_RHX('localhost', 5000, Connect=false);
    rt10 = epsych.Runtime;
    rt10.DefaultDataPath = "C:/Data";
    rt10.isTest = false;
    rt10.SessionDataFilename = "C:/Data/Rat1/Rat1_260716T101530.mat";
    iface10.prepareRecording(rt10);
    assert_ok('prepareRecording offline no-op', isempty(iface10.ActiveRecordingFile));
catch ME
    fprintf('  FAIL  prepareRecording offline: %s\n', ME.message);
end

%% 11. hw.Interface.prepareRecording default is a no-op (via hw.Software)
try
    sw11 = hw.Software();
    rt11 = epsych.Runtime;
    sw11.prepareRecording(rt11);   % must not throw
    assert_ok('hw.Interface.prepareRecording no-op for Software', true);
catch ME
    fprintf('  FAIL  base prepareRecording: %s\n', ME.message);
end

%% 12. RecordingRootDir stays per-machine; SettingsFile is now protocol-level
try
    iface12 = hw.Intan_RHX('192.168.1.50', 5001, Connect=false);
    m12 = hw.Module(iface12, 'RHX', 'RHX', uint8(1));
    iface12.setModules(m12);
    iface12.RecordingRootDir = 'C:/IntanData';
    iface12.SettingsFile = 'C:/cfg/rhx.xml';

    prot12 = epsych.Protocol();
    prot12.addInterface(iface12);
    s12 = prot12.toStruct();
    ii = find(cellfun(@(d) strcmp(d.Type,'Intan_RHX'), s12.InterfaceData), 1);
    ifS = s12.InterfaceData{ii};
    % RecordingRootDir is per-machine and must not travel in the .eprot.
    assert_ok('toStruct omits RecordingRootDir', ~isfield(ifS, 'RecordingRootDir'));
    % SettingsFile is now protocol-level configuration and does serialize.
    assert_ok('toStruct serializes SettingsFile', ...
        isfield(ifS, 'SettingsFile') && strcmp(ifS.SettingsFile, 'C:/cfg/rhx.xml'));
catch ME
    fprintf('  FAIL  pref/config serialization: %s\n', ME.message);
end

fprintf('\n=== Done ===\n\n');
