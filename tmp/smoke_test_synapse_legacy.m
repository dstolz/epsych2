% smoke_test_synapse_legacy.m
% Standing proof for hw.TDT_Synapse against a processor in LEGACY mode --
% Synapse loading an RPvdsEx circuit whole and exposing its parameter tags
% as the processor's own parameters -- with no Synapse and no hardware.
%
% Drives the real backend through tmp/TDT_Synapse_Mock, which swaps a
% tmp/SynapseAPI_Mock in at the one seam where a client is constructed.
% The mock answers with what the SynapseAPI manual documents and what the
% lab's 2018-2021 integration observed on the rig: the legacy processor is
% its own gizmo with no parent; Type is 'Float'/'Int'/'Logic'; Array is
% 'Yes' at design time and a count at runtime; some tags are listed but
% not described; parameter access is refused in Idle; Standby can be
% disabled in Synapse's preferences.
%
% Groups:
%   1  parameterSpecFromInfo: the Synapse -> hw.Parameter vocabulary
%   2  filterParameterNames: what a legacy circuit lists that is not a parameter
%   3  discovery: modules from a legacy processor beside ordinary gizmos
%   4  a protocol-authored module survives connect; an unknown Label does not
%   5  scalar and array writes and reads through hw.Parameter and directly
%   6  a stimulus lands in the circuit's buffer tag at the device rate
%   7  triggers pulse and report failure
%   8  mode mapping, Standby refused, connect from Record
%   9  readHardwareParameters offline at design time
%  10  disconnect, reconnect, and the metadata round trip
%
% Run headless:
%   matlab -batch "run('tmp/smoke_test_synapse_legacy.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('epsych_startup'))
    addpath(repoRoot);
end
if isempty(which('hw.Module'))
    epsych_startup
end
addpath(fileparts(mfilename('fullpath'))); % the mocks live beside this script

fprintf('\n=== hw.TDT_Synapse legacy-mode Smoke Test ===\n\n');

failures = 0;

RZ6_FS = 48828.125;
RZ2_FS = 24414.0625;

%% 1. parameterSpecFromInfo: Synapse vocabulary -> hw.Parameter
try
    info = struct('Name','NTrials','Unit','','Min',nan,'Max',nan,'Access','Both','Type','Int','Array','No');
    [s, notes] = hw.TDT_Synapse.parameterSpecFromInfo('NTrials', info);
    failures = failures + assert_ok('1  Int -> Integer', strcmp(s.Type, 'Integer'));
    failures = failures + assert_ok('1  Both -> Any', strcmp(s.Access, 'Any'));
    failures = failures + assert_ok('1  NaN bounds -> [-Inf Inf]', s.Min == -inf && s.Max == inf);
    failures = failures + assert_ok('1  ''No'' -> scalar, no size', ~s.isArray && isnan(s.Size));
    failures = failures + assert_ok('1  described cleanly: no notes', s.Described && isempty(notes));

    info.Type = 'Logic';
    s = hw.TDT_Synapse.parameterSpecFromInfo('Resp', info);
    failures = failures + assert_ok('1  Logic -> Boolean', strcmp(s.Type, 'Boolean'));

    info.Type = 'Float'; info.Min = 100; info.Max = 20000; info.Unit = 'Hz';
    s = hw.TDT_Synapse.parameterSpecFromInfo('Freq', info);
    failures = failures + assert_ok('1  Float with bounds and unit', ...
        strcmp(s.Type, 'Float') && s.Min == 100 && s.Max == 20000 && strcmp(s.Unit, 'Hz'));

    info.Array = 'Yes';     % design time: size unknown
    s = hw.TDT_Synapse.parameterSpecFromInfo('Stim', info);
    failures = failures + assert_ok('1  Array ''Yes'' -> Buffer, isArray, size unknown', ...
        strcmp(s.Type, 'Buffer') && s.isArray && isnan(s.Size));

    info.Array = 100000;    % runtime: the count
    s = hw.TDT_Synapse.parameterSpecFromInfo('Stim', info);
    failures = failures + assert_ok('1  Array 100000 -> Buffer with size', ...
        strcmp(s.Type, 'Buffer') && s.isArray && s.Size == 100000);

    info.Array = 1;
    s = hw.TDT_Synapse.parameterSpecFromInfo('Freq', info);
    failures = failures + assert_ok('1  Array 1 -> scalar Float', strcmp(s.Type, 'Float') && ~s.isArray);

    accessCases = {'Read', 'Read'; 'Write', 'Write'; 'Read/Write', 'Any'; 'ReadWrite', 'Any'; ...
        'both', 'Any'; 'R', 'Read'; 'W', 'Write'};
    okAccess = true;
    for k = 1:size(accessCases, 1)
        info.Access = accessCases{k, 1};
        s = hw.TDT_Synapse.parameterSpecFromInfo('Freq', info);
        okAccess = okAccess && strcmp(s.Access, accessCases{k, 2});
    end
    failures = failures + assert_ok('1  access words map by meaning', okAccess);

    info.Access = '';
    [s, notes] = hw.TDT_Synapse.parameterSpecFromInfo('Freq', info);
    failures = failures + assert_ok('1  blank access -> Any, noted', strcmp(s.Access, 'Any') && ...
        numel(notes) == 1 && contains(notes(1), 'access'));

    info.Access = 'Both'; info.Type = 'Enum';
    [s, notes] = hw.TDT_Synapse.parameterSpecFromInfo('Sel', info);
    failures = failures + assert_ok('1  unknown type -> Undefined, noted', strcmp(s.Type, 'Undefined') && ...
        numel(notes) == 1 && contains(notes(1), 'Enum'));

    [s, notes] = hw.TDT_Synapse.parameterSpecFromInfo('!Trig', struct());
    failures = failures + assert_ok('1  undescribed trigger -> Undefined trigger, Any, not Described', ...
        ~s.Described && s.isTrigger && strcmp(s.Type, 'Undefined') && strcmp(s.Access, 'Any') && isempty(notes));

    s = hw.TDT_Synapse.parameterSpecFromInfo('Mystery', []);
    failures = failures + assert_ok('1  undescribed scalar -> Undefined', ~s.Described && strcmp(s.Type, 'Undefined'));

    v = @(n) visible_of(n, info);
    failures = failures + assert_ok('1  ~, _ and # hide; others show', ...
        ~v('~BoxID') && ~v('_Int') && ~v('#X') && v('Freq') && v('!Trig'));

    info.Type = 'Float'; info.Min = 10; info.Max = 1;
    [s, notes] = hw.TDT_Synapse.parameterSpecFromInfo('Bad', info);
    failures = failures + assert_ok('1  reversed bounds -> none, noted', s.Min == -inf && s.Max == inf && ~isempty(notes));

    info.Min = '5'; info.Max = 'abc';
    [s, notes] = hw.TDT_Synapse.parameterSpecFromInfo('Txt', info);
    failures = failures + assert_ok('1  text bounds: numeric read, junk noted', s.Min == 5 && s.Max == inf && numel(notes) == 1);

    % What a live Synapse said of every tag of a legacy circuit while Idle.
    info = struct('Name','ITIDur','Unit','','Min',-1e20,'Max',1e20,'Access','Read / Write','Type','Float','Array','No');
    [s, notes] = hw.TDT_Synapse.parameterSpecFromInfo('ITIDur', info);
    failures = failures + assert_ok('1  a legacy tag at Idle: ''Read / Write'' -> Any, +/-1e20 -> unbounded, no notes', ...
        strcmp(s.Access, 'Any') && s.Min == -inf && s.Max == inf && strcmp(s.Type, 'Float') && isempty(notes));
    % The runtime's required names are ordinary parameters to discovery, as
    % they are to hw.TDT_RPcox over the same circuit; the protocol's author
    % marks the pulsed two as triggers in ProtocolDesigner.
    s = hw.TDT_Synapse.parameterSpecFromInfo('x_NewTrial_1', info);
    failures = failures + assert_ok('1  x_NewTrial_<box> is an ordinary visible Float, as under RPcox', ...
        ~s.isTrigger && s.Visible && strcmp(s.Type, 'Float') && strcmp(s.Access, 'Any'));
    s = hw.TDT_Synapse.parameterSpecFromInfo('_RespCode_1', info);
    failures = failures + assert_ok('1  _RespCode_<box> is hidden by its prefix', ~s.isTrigger && ~s.Visible);
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 1: %s\n', ME.message);
end

%% 2. filterParameterNames
try
    [keep, dropped] = hw.TDT_Synapse.filterParameterNames( ...
        {'Freq', '%junk', 'a/b', 'rPvDsHElpEr1', '#Hidden', 'has space', '~BoxID', '!Trig', '_Int', 'x|y'});
    failures = failures + assert_ok('2  keeps every addressable tag in order', ...
        isequal(keep, {'Freq', '~BoxID', '!Trig', '_Int'}));
    failures = failures + assert_ok('2  drops the rest with a reason each', ...
        numel(dropped) == 6 && all(arrayfun(@(d) ~isempty(d.Reason), dropped)));
    failures = failures + assert_ok('2  # is reported as unaddressable', ...
        contains(dropped(strcmp({dropped.Name}, '#Hidden')).Reason, 'HTTP'));
    [keep, dropped] = hw.TDT_Synapse.filterParameterNames(string({'A', 'B'}));
    failures = failures + assert_ok('2  accepts a string array; empty dropped list is a struct', ...
        isequal(keep, {'A', 'B'}) && isstruct(dropped) && isempty(dropped));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 2: %s\n', ME.message);
end

%% 3. Discovery against a legacy experiment
try
    api = SynapseAPI_Mock();
    lastwarn('');
    I = TDT_Synapse_Mock(api, Connect = true);
    failures = failures + assert_ok('3  connected, Synapse in Standby', I.IsConnected && api.Mode == 1 && I.mode == hw.DeviceState.Standby);
    failures = failures + assert_ok('3  no 404 provoked: no parent asked of a processor, no block asked in Standby', ...
        isempty(lastwarn) && isempty(I.ExperimentInfo.block));
    failures = failures + assert_ok('3  one module per object with API parameters', ...
        isequal({I.Module.Label}, {'RZ6(1)', 'PulseGen1'}));
    failures = failures + assert_ok('3  names and indices from the listing', ...
        strcmp(I.Module(1).Name, 'RZ6') && I.Module(1).Index == 1 && ...
        strcmp(I.Module(2).Name, 'PulseGen1') && I.Module(2).Index == 2);
    failures = failures + assert_ok('3  legacy processor flagged, gizmo not', ...
        I.isLegacyModule(I.Module(1)) && ~I.isLegacyModule(I.Module(2)));
    failures = failures + assert_ok('3  legacy rate under its own name (no parent)', ...
        I.Module(1).Fs == RZ6_FS && isempty(I.Module(1).Info.Processor));
    failures = failures + assert_ok('3  gizmo rate from its parent processor', ...
        I.Module(2).Fs == RZ2_FS && strcmp(I.Module(2).Info.Processor, 'RZ2_1'));
    failures = failures + assert_ok('3  category recorded', strcmp(I.Module(1).Info.Category, 'Legacy'));

    names = arrayfun(@(p) p.Name, I.Module(1).Parameters, 'UniformOutput', false);
    failures = failures + assert_ok('3  circuit tags exposed, junk and unaddressable dropped', ...
        isequal(names, {'Freq', 'NTrials', 'Resp', '~BoxID', '!Trig', 'Stim', 'StimSmall', ...
        'x_NewTrial_1', 'x_ResetTrig_1', 'x_TrialComplete_1', 'x_TrialNum_1', '_RespCode_1'}));
    Pnt = I.find_parameter('x_NewTrial_1');
    Prc = I.find_parameter('_RespCode_1', includeInvisible = true);
    failures = failures + assert_ok('3  the runtime''s required names are ordinary parameters until the author marks them', ...
        ~Pnt.isTrigger && Pnt.Visible && strcmp(Pnt.Access, 'Any') && ~Prc.Visible);
    failures = failures + assert_ok('3  NTrials: +/-1e20 from Synapse is no bound', ...
        I.find_parameter('NTrials').Min == -inf && I.find_parameter('NTrials').Max == inf);

    P = I.find_parameter('Freq');
    failures = failures + assert_ok('3  Freq: Float, Any, [100 20000] Hz, visible', ...
        strcmp(P.Type, 'Float') && strcmp(P.Access, 'Any') && P.Min == 100 && P.Max == 20000 && ...
        strcmp(P.Unit, 'Hz') && P.Visible);
    failures = failures + assert_ok('3  NTrials: Integer', strcmp(I.find_parameter('NTrials').Type, 'Integer'));
    Pr = I.find_parameter('Resp');
    failures = failures + assert_ok('3  Resp: Boolean, read-only', strcmp(Pr.Type, 'Boolean') && strcmp(Pr.Access, 'Read'));
    Pb = I.find_parameter('~BoxID', includeInvisible = true);
    failures = failures + assert_ok('3  ~BoxID: hidden Integer', ~Pb.Visible && strcmp(Pb.Type, 'Integer'));
    Pt = I.find_parameter('!Trig');
    failures = failures + assert_ok('3  !Trig listed but undescribed: still a trigger', ...
        Pt.isTrigger && strcmp(Pt.Type, 'Undefined') && ~isfield(Pt.UserData, 'SynapseInfo'));
    Ps = I.find_parameter('Stim');
    failures = failures + assert_ok('3  Stim: Buffer from a runtime count, raw info kept', ...
        strcmp(Ps.Type, 'Buffer') && Ps.isArray && isequal(Ps.UserData.SynapseInfo.Array, 100000));
    failures = failures + assert_ok('3  hardware name recorded', ...
        strcmp(hw.Interface.getHardwareParameterName(Ps), 'Stim'));
    failures = failures + assert_ok('3  thirteen parameters in all', ...
        numel(I.all_parameters(includeInvisible = true, includeTriggers = true)) == 13);
    failures = failures + assert_ok('3  experiment info read', strcmp(I.ExperimentInfo.subject, 'M1'));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 3: %s\n', ME.message);
end

%% 4. A protocol-authored module survives connect; an unknown Label does not
try
    api4 = SynapseAPI_Mock();
    I4 = TDT_Synapse_Mock(api4);
    M = hw.Module(I4, 'RZ6(1)', 'RZ6', uint8(1));
    Mg = hw.Module(I4, 'PulseGen1', 'Pulse', uint8(2));
    I4.setModules([M Mg]);
    Pf = M.add_parameter('Freq', {1000, 2000}, Type = 'Float');
    M.add_parameter('Gone', 5, Type = 'Float'); % no such tag: reported, not fatal
    M.add_parameter('Stim', 0, Type = 'Float'); % a buffer a design-time read called a scalar
    out = evalc('I4.connect();');
    failures = failures + assert_ok('4  the authored module is the bound module', ...
        I4.IsConnected && numel(I4.Module) == 2 && I4.Module(1) == M);
    failures = failures + assert_ok('4  authored parameters kept, not rediscovered', ...
        numel(M.Parameters) == 3 && isequal(Pf.Values, {1000, 2000}) && strcmp(M.Parameters(3).Type, 'Float'));
    failures = failures + assert_ok('4  a tag the circuit lacks is reported once', ...
        contains(out, 'no tag') && contains(out, 'Gone'));
    failures = failures + assert_ok('4  a buffer typed as a scalar is reported once, with its size', ...
        contains(out, 'arrays on the device') && contains(out, 'Stim (100000 elements)'));
    failures = failures + assert_ok('4  server-side facts filled in', ...
        M.Fs == RZ6_FS && I4.isLegacyModule(M));
    failures = failures + assert_ok('4  an authored module with no parameters is populated', ...
        numel(Mg.Parameters) == 1 && strcmp(Mg.Parameters(1).Name, 'PulseFreq') && Mg.Fs == RZ2_FS);

    % The Synapse name in the module's Name and a display name in its Label,
    % as hw.Module's own documentation reads: accepted, and every call is
    % still addressed to the Synapse name.
    api4b = SynapseAPI_Mock();
    I4b = TDT_Synapse_Mock(api4b);
    Mb = hw.Module(I4b, 'Behavior', 'RZ6(1)', uint8(1));
    I4b.setModules(Mb);
    I4b.connect();
    Pb4 = I4b.find_parameter('Freq');
    api4b.clearLog();
    Pb4.Value = 2500;
    lastWrite = api4b.lastCall('setParameterValue');
    failures = failures + assert_ok('4  the Synapse name is accepted in the Name field', ...
        I4b.IsConnected && strcmp(Mb.Info.SynapseName, 'RZ6(1)') && I4b.isLegacyModule(Mb) && Mb.Fs == RZ6_FS);
    failures = failures + assert_ok('4  ... and I/O is addressed to it, not the Label', ...
        numel(lastWrite) == 3 && strcmp(lastWrite{1}, 'RZ6(1)') && api4b.value('RZ6(1)', 'Freq') == 2500);

    api5 = SynapseAPI_Mock();
    I5 = TDT_Synapse_Mock(api5);
    I5.setModules(hw.Module(I5, 'RZ6', 'Behavior', uint8(1)));
    [n, ME5] = expect_error(@() I5.connect(), 'hw:TDT_Synapse:UnknownGizmo');
    failures = failures + n;
    failures = failures + assert_ok('4  the error names both fields and what Synapse has', ...
        ~isempty(ME5) && contains(ME5.message, 'RZ6(1)') && contains(ME5.message, 'PulseGen1') && ...
        contains(ME5.message, 'Behavior') && contains(ME5.message, '"RZ6"'));
    failures = failures + assert_ok('4  a refused connect leaves nothing behind', ...
        ~I5.IsConnected && isempty(I5.HW) && api5.Mode == 0);

    api6 = SynapseAPI_Mock(Experiment = SynapseAPI_Mock.gizmo('RZ2(1)', 'Hardware Access', 'RZ2', '', SynapseAPI_Mock.param()));
    I6 = TDT_Synapse_Mock(api6);
    [n, ~] = expect_error(@() I6.connect(), 'hw:TDT_Synapse:NoApiParameters');
    failures = failures + n;
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 4: %s\n', ME.message);
end

%% 5. Scalar and array writes and reads
try
    api.clearLog();
    P.Value = 4000;
    failures = failures + assert_ok('5  scalar write through hw.Parameter', ...
        api.value('RZ6(1)', 'Freq') == 4000 && isequal(api.lastCall('setParameterValue'), {'RZ6(1)', 'Freq', 4000}));

    Pn = I.find_parameter('NTrials');
    Pn.Value = true;
    failures = failures + assert_ok('5  logical written as a number', isequal(api.value('RZ6(1)', 'NTrials'), 1));

    Ps.Value = sin(1:1000);
    written = api.value('RZ6(1)', 'Stim');
    failures = failures + assert_ok('5  array write goes through setParameterValues', ...
        strcmp(second_arg(api.lastCall('setParameterValues')), 'Stim') && isequal(written(1:1000), sin(1:1000)) && ...
        numel(written) == 100000);

    e = I.set_parameter(Ps, [7 8 9]);
    written = api.value('RZ6(1)', 'Stim');
    failures = failures + assert_ok('5  a bare array handed to one parameter is that parameter''s value', ...
        e && isequal(written(1:3), [7 8 9]));

    before = api.callCount('setParameterValue');
    e = I.set_parameter(P, []);
    failures = failures + assert_ok('5  empty value: nothing written, reported as fine', ...
        e && api.callCount('setParameterValue') == before);
    e = I.set_parameter(P, 'abc');
    failures = failures + assert_ok('5  text value: nothing written', ...
        e && api.callCount('setParameterValue') == before);

    e = I.set_parameter([P Pn], [5000 3]);
    failures = failures + assert_ok('5  one value per parameter', ...
        e && api.value('RZ6(1)', 'Freq') == 5000 && api.value('RZ6(1)', 'NTrials') == 3);
    e = I.set_parameter([P Pn], 9);
    failures = failures + assert_ok('5  one value for every parameter', ...
        e && api.value('RZ6(1)', 'Freq') == 9 && api.value('RZ6(1)', 'NTrials') == 9);

    api.Mode = 0;
    e = I.set_parameter(P, 1);
    failures = failures + assert_ok('5  a refused write reports false', ~e);
    v = I.get_parameter(P);
    failures = failures + assert_ok('5  a refused read is NaN', isnan(v));
    api.Mode = 1;

    api.setParameterValue('RZ6(1)', 'Freq', 1234);
    failures = failures + assert_ok('5  hw.Parameter.Value reads the device', P.Value == 1234);
    vals = I.get_parameter([P Pn]);
    failures = failures + assert_ok('5  batch read keeps order', iscell(vals) && vals{1} == 1234 && vals{2} == 9);
    stimRead = Ps.Value;
    arrayRead = api.lastCall('getParameterValues');
    failures = failures + assert_ok('5  array read goes through getParameterValues WITH its count', ...
        numel(stimRead) == 100000 && numel(arrayRead) == 3 && strcmp(arrayRead{2}, 'Stim') && arrayRead{3} == 100000);

    % A scalar tag the protocol marks isArray (the rig's TrialType): read as
    % the scalar the device says it is, through getParameterValue.
    api.clearLog();
    Pn.isArray = true;
    v = Pn.Value;
    Pn.isArray = false;
    failures = failures + assert_ok('5  a scalar tag marked isArray is read as a scalar', ...
        v == 9 && api.callCount('getParameterValue') == 1 && api.callCount('getParameterValues') == 0);

    api.ReadErrors = {'Resp'};
    v = I.get_parameter(Pr);
    api.ReadErrors = {};
    failures = failures + assert_ok('5  a read that throws is that parameter''s NaN, not the session''s end', isnan(v));
    failures = failures + assert_ok('5  hidden parameter readable by name', ...
        I.get_parameter('~BoxID', includeInvisible = true) == 1);
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 5: %s\n', ME.message);
end

%% 6. A stimulus lands in the circuit's buffer tag at the device rate
try
    tone = stimgen.Tone();
    tone.Duration = 0.05;
    Ps.Type = 'StimType'; % as the protocol's author would
    api.clearLog();
    Ps.Value = tone;
    written = api.value('RZ6(1)', 'Stim');
    failures = failures + assert_ok('6  stimulus regenerated at the module rate', tone.Fs == RZ6_FS);
    failures = failures + assert_ok('6  the signal is in the buffer tag', ...
        tone.N > 0 && isequal(written(1:tone.N), reshape(tone.Signal, 1, [])) && ...
        strcmp(second_arg(api.lastCall('setParameterValues')), 'Stim'));

    Pss = I.find_parameter('StimSmall');
    Pss.Type = 'StimType';
    api.clearLog();
    ok = I.set_parameter(Pss, tone);
    failures = failures + assert_ok('6  a stimulus longer than the tag is refused, not truncated', ...
        ~ok && api.callCount('setParameterValues') == 0 && ~any(api.value('RZ6(1)', 'StimSmall')));

    ok = I.set_parameter(Ps, stimgen.Tone.empty(1, 0));
    failures = failures + assert_ok('6  no stimulus chosen: nothing to write', ok);
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 6: %s\n', ME.message);
end

%% 7. Triggers pulse and report failure
try
    api.clearLog();
    t = I.trigger(Pt);
    edges = cellfun(@(c) c{4}, api.Log(cellfun(@(c) strcmp(c{1}, 'setParameterValue'), api.Log)));
    failures = failures + assert_ok('7  one pulse: high then low', isequal(edges, [1 0]));
    failures = failures + assert_ok('7  returns a datenum, as lastUpdated stores', isa(t, 'double') && t > 7e5);
    Pt.Trigger();
    failures = failures + assert_ok('7  hw.Parameter.Trigger reaches the backend', Pt.lastUpdated > 7e5);
    api.clearLog();
    Pnt.Trigger(); % refused: not marked, exactly as under RPcox
    failures = failures + assert_ok('7  an unmarked x_NewTrial_1 does not fire', api.callCount('setParameterValue') == 0);
    Pnt.isTrigger = true; % what ProtocolDesigner does for an RPcox protocol over the same circuit
    Pnt.Trigger();
    failures = failures + assert_ok('7  marked in the protocol, x_NewTrial_1 fires like any trigger', ...
        api.callCount('setParameterValue') == 2 && Pnt.lastUpdated > 7e5);

    api.Mode = 0;
    [n, ~] = expect_error(@() I.trigger(Pt), 'hw:TDT_Synapse:TriggerFailed');
    failures = failures + n;
    api.Mode = 1;
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 7: %s\n', ME.message);
end

%% 8. Mode mapping, Standby refused, connect from Record
try
    I.mode = hw.DeviceState.Record;
    failures = failures + assert_ok('8  Record', api.Mode == 3 && I.mode == hw.DeviceState.Record);
    failures = failures + assert_ok('8  the block is read once there is one', strcmp(I.ExperimentInfo.block, 'M1-260101'));
    I.mode = hw.DeviceState.Idle;
    failures = failures + assert_ok('8  Idle', api.Mode == 0);

    % Synapse answers a mode request before the change is done (the rig's
    % 503 on Preview -> Idle): the mode is polled for, not read from the reply.
    api.SlowTransitions = 3;
    I.mode = hw.DeviceState.Preview;
    failures = failures + assert_ok('8  a slow mode change is waited for', api.Mode == 2 && I.mode == hw.DeviceState.Preview);
    api.SlowTransitions = 0;

    api.SlowTransitions = 1e6;
    I.ModeTimeout = 0.6;
    [n, ME8b] = expect_error(@() set(I, 'mode', hw.DeviceState.Idle), 'hw:TDT_Synapse:ModeRejected');
    failures = failures + n;
    failures = failures + assert_ok('8  ... but not forever, and the message says where it is', ...
        ~isempty(ME8b) && contains(ME8b.message, 'Preview') && contains(ME8b.message, '0.6 s'));
    api.settle();
    I.ModeTimeout = 20;
    I.mode = hw.DeviceState.Idle;
    I.mode = hw.DeviceState.Preview;
    I.mode = hw.DeviceState.Stop;
    failures = failures + assert_ok('8  Stop lands in Idle', api.Mode == 0);
    I.mode = hw.DeviceState.Pause;
    failures = failures + assert_ok('8  Pause lands in Standby', api.Mode == 1);

    api8 = SynapseAPI_Mock();
    api8.StandbyEnabled = false;
    I8 = TDT_Synapse_Mock(api8);
    [n, ME8] = expect_error(@() I8.connect(), 'hw:TDT_Synapse:ModeRejected');
    failures = failures + n;
    failures = failures + assert_ok('8  the refusal names the Preferences remedy', ...
        ~isempty(ME8) && contains(ME8.message, 'Preferences'));
    failures = failures + assert_ok('8  nothing left connected', ~I8.IsConnected && isempty(I8.HW) && api8.Mode == 0);

    api9 = SynapseAPI_Mock();
    api9.Mode = 3;
    I9 = TDT_Synapse_Mock(api9, Connect = true);
    modes = cellfun(@(c) c{2}, api9.Log(cellfun(@(c) strcmp(c{1}, 'setMode'), api9.Log)));
    failures = failures + assert_ok('8  a server found in Record is taken through Idle to Standby', ...
        isequal(modes, [0 1]) && api9.Mode == 1);
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 8: %s\n', ME.message);
end

%% 9. readHardwareParameters offline at design time
try
    api10 = SynapseAPI_Mock(); % Idle: Array answers 'Yes'
    I10 = TDT_Synapse_Mock(api10);
    M10 = hw.Module(I10, 'RZ6(1)', 'RZ6', uint8(1));
    M11 = hw.Module(I10, 'RZ6', 'RZ6 wrong', uint8(2));
    I10.setModules([M10 M11]);

    [tf, msg] = I10.readHardwareParameters(M10);
    failures = failures + assert_ok('9  reads without connecting or touching the mode', ...
        tf && ~I10.IsConnected && api10.Mode == 0 && api10.callCount('setMode') == 0);
    failures = failures + assert_ok('9  twelve parameters, legacy flagged, rate known', ...
        numel(M10.Parameters) == 12 && I10.isLegacyModule(M10) && M10.Fs == RZ6_FS && contains(msg, 'legacy'));
    PsOff = M10.Parameters(strcmp({M10.Parameters.Name}, 'Stim'));
    failures = failures + assert_ok('9  design-time ''Yes'' still makes a Buffer', ...
        strcmp(PsOff.Type, 'Buffer') && PsOff.isArray);

    [tf, msg] = I10.readHardwareParameters(M10);
    failures = failures + assert_ok('9  merge is idempotent', tf && numel(M10.Parameters) == 12 && contains(msg, '12 already present'));
    M10.Parameters(end) = [];
    [tf, ~] = I10.readHardwareParameters(M10, Mode = 'replace');
    failures = failures + assert_ok('9  replace rebuilds from the server', tf && numel(M10.Parameters) == 12);

    [tf, msg] = I10.readHardwareParameters(M11);
    failures = failures + assert_ok('9  unknown Label: declined, naming the objects Synapse has', ...
        ~tf && contains(msg, 'RZ6(1)') && isempty(M11.Parameters));

    I10b = TDT_Synapse_Mock(SynapseAPI_Mock());
    M12 = hw.Module(I10b, 'Behavior', 'RZ6(1)', uint8(1));
    I10b.setModules(M12);
    [tf, ~] = I10b.readHardwareParameters(M12);
    failures = failures + assert_ok('9  the Synapse name in the Name field is read too', ...
        tf && numel(M12.Parameters) == 12 && strcmp(M12.Info.SynapseName, 'RZ6(1)'));

    [tf, msg] = I10.readHardwareParameters(I.Module(1));
    failures = failures + assert_ok('9  another interface''s module is declined', ~tf && contains(msg, 'does not belong'));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 9: %s\n', ME.message);
end

%% 10. Disconnect, reconnect, and the metadata round trip
try
    I.disconnect();
    failures = failures + assert_ok('10 disconnect returns Synapse to Idle', ~I.IsConnected && isempty(I.HW) && api.Mode == 0);
    I.connect();
    failures = failures + assert_ok('10 reconnect keeps the modules', ...
        I.IsConnected && api.Mode == 1 && isequal({I.Module.Label}, {'RZ6(1)', 'PulseGen1'}) && ...
        numel(I.Module(1).Parameters) == 12);

    S = Pn.toStruct();
    Q = hw.Parameter(I);
    Q.Module = I.Module(1);
    Q.fromStruct(S, false);
    failures = failures + assert_ok('10 discovered metadata survives a protocol round trip', ...
        strcmp(Q.Type, 'Integer') && strcmp(Q.Access, 'Any') && ...
        strcmp(Q.UserData.SynapseInfo.Type, 'Int') && strcmp(hw.Interface.getHardwareParameterName(Q), 'NTrials'));

    results = I.selfTest(Invasive = true);
    failures = failures + assert_ok('10 invasive self-test passes and reports the legacy module', ...
        all([results.status] == "pass") && any(contains([results.detail], 'legacy')));
    I.disconnect();
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 10: %s\n', ME.message);
end

%% Summary
fprintf('\n=== %s: %d failure(s) ===\n', mfilename, failures);
if failures > 0
    error('smoke_test_synapse_legacy:failed', '%d assertion(s) failed.', failures);
end


function nFail = assert_ok(label, expr)
    if expr
        fprintf('  PASS  %s\n', label);
        nFail = 0;
    else
        fprintf('  FAIL  %s\n', label);
        nFail = 1;
    end
end


function tf = visible_of(name, info)
    s = hw.TDT_Synapse.parameterSpecFromInfo(name, info);
    tf = s.Visible;
end


function a = second_arg(args)
    % The gizmo-qualified parameter name is the second argument of every
    % parameter call the mock logs; '' when the call never happened.
    a = '';
    if numel(args) >= 2
        a = args{2};
    end
end


function [nFail, ME] = expect_error(fcn, id)
    ME = MException.empty;
    try
        fcn();
        fprintf('  FAIL  expected error %s, none thrown\n', id);
        nFail = 1;
    catch ME
        if strcmp(ME.identifier, id)
            fprintf('  PASS  throws %s\n', id);
            nFail = 0;
        else
            fprintf('  FAIL  expected %s, got %s: %s\n', id, ME.identifier, ME.message);
            nFail = 1;
        end
    end
end
