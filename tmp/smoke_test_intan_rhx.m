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
    assert_ok('spec has host option',   any(strcmp(optNames, 'host')));
    assert_ok('spec has port option',   any(strcmp(optNames, 'port')));
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
catch ME
    fprintf('  FAIL  createFcn: %s\n', ME.message);
end

fprintf('\n=== Done ===\n\n');
