% smoke_test_phase_parent_type_fallback.m
% Standing proof that a phase file saved against one TDT backend loads into
% a session running the other: epsych.Runtime.readParameters applies an
% entry whose recorded ParentType has no interface in the session to the
% interfaces that type is interchangeable with
% (epsych.Runtime.INTERCHANGEABLE_PARENT_TYPES), and nowhere else.
%
% The case it exists for: a lab's phase library saved under hw.TDT_RPcox,
% every entry stamped ParentType 'TDT_RPcox', loaded into a hw.TDT_Synapse
% session driving the same circuit in legacy mode -- which skipped all 31
% parameters with "No matching interface found" on 2026-10-07.
%
% No hardware: the RPcox interface stays offline (RunOffline), the Synapse
% one is tmp/TDT_Synapse_Mock over tmp/SynapseAPI_Mock.
%
% Groups:
%   1  RPcox phase -> Synapse session: tags land on the Synapse module, a
%      Software entry still lands on Software, a tag the Synapse module
%      lacks is skipped, the crossing is reported once
%   2  Synapse phase -> RPcox session (the reverse)
%   3  a type outside the group still finds nothing
%   4  an exact-type interface is always preferred to a fallback
%
% Run headless:
%   matlab -batch "run('tmp/smoke_test_phase_parent_type_fallback.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('epsych_startup'))
    addpath(repoRoot);
end
if isempty(which('hw.Module'))
    epsych_startup
end
addpath(fileparts(mfilename('fullpath')));

fprintf('\n=== Phase ParentType fallback Smoke Test ===\n\n');

failures = 0;
tmpDir = fullfile(tempdir, sprintf('epsych_phase_fallback_%s', datestr(now, 'yyyymmddHHMMSSFFF')));
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

%% Fixtures
% The circuit both backends drive, as the Synapse mock lists it.
circuit = SynapseAPI_Mock.gizmo('RZ6(1)', 'Legacy', 'LegacyHal', '', [ ...
    SynapseAPI_Mock.param('TimeoutDur', 'Float', 'Read / Write', Min = -1e20, Max = 1e20), ...
    SynapseAPI_Mock.param('TrialType',  'Float', 'Read / Write', Min = -1e20, Max = 1e20), ...
    SynapseAPI_Mock.param('Norm',       'Float', 'Read / Write', Min = -1e20, Max = 1e20), ...
    SynapseAPI_Mock.param('Shape',      'Float', 'Read / Write', Min = -1e20, Max = 1e20)]);
rates = struct('RZ6_1', 48828.125);

% Protocol A: Software + TDT_RPcox, the one the phase library was saved from.
% Values are set explicitly: add_parameter fills the design-time Values and
% leaves Value empty, and a phase carries Value.
PA = epsych.Protocol(Name = 'RPcoxSide', Info = 'phase fallback');
swA = PA.Interfaces(1);
add_with_value(swA.Module, 'RespWinPreStim', 0.2, 'Float');
add_with_value(swA.Module, 'Norm', 3, 'Float');
rp = hw.TDT_RPcox({}, {}, {}, Connect = false);
MA = hw.Module(rp, 'RZ6', 'Behavior', uint8(1));
rp.setModules(MA);
add_with_value(MA, 'TimeoutDur', 100, 'Float');
add_with_value(MA, 'TrialType', 1, 'Integer');
add_with_value(MA, 'Norm', 7, 'Float');
add_with_value(MA, 'Shape', false, 'Boolean'); % no counterpart on the Synapse module
PA.addInterface(rp);
rpcoxPhase = fullfile(tmpDir, 'rpcox_phase.eprot');
PA.save(rpcoxPhase);

% Protocol B: Software + TDT_Synapse over the same circuit.
PB = epsych.Protocol(Name = 'SynapseSide', Info = 'phase fallback');
swB = PB.Interfaces(1);
add_with_value(swB.Module, 'RespWinPreStim', 0.9, 'Float');
add_with_value(swB.Module, 'Norm', 1, 'Float');
api = SynapseAPI_Mock(Experiment = circuit, Rates = rates);
syn = TDT_Synapse_Mock(api);
MB = hw.Module(syn, 'RZ6(1)', 'Behavior', uint8(1));
syn.setModules(MB);
add_with_value(MB, 'TimeoutDur', 5, 'Float');
add_with_value(MB, 'TrialType', 0, 'Integer');
add_with_value(MB, 'Norm', 0, 'Float');
PB.addInterface(syn);

%% 1. RPcox phase -> Synapse session
try
    R = epsych.Runtime;
    R.isTest = true;
    R.EVENTS = epsych.EventHub;
    R.Interfaces = PB.Interfaces; % connects the Synapse mock
    R.Protocol = PB;

    out = evalc('R.readParameters(rpcoxPhase);');

    failures = failures + assert_ok('1  tags saved under TDT_RPcox land on the TDT_Synapse module', ...
        api.value('RZ6(1)', 'TimeoutDur') == 100 && api.value('RZ6(1)', 'TrialType') == 1);
    failures = failures + assert_ok('1  the Software entry still lands on Software, not across', ...
        swB.find_parameter('RespWinPreStim').Value == 0.2 && swB.find_parameter('Norm').Value == 3);
    failures = failures + assert_ok('1  a same-named tag goes to the module, not to Software', ...
        api.value('RZ6(1)', 'Norm') == 7);
    failures = failures + assert_ok('1  no "No matching interface" for any TDT_RPcox entry', ...
        ~contains(out, 'No matching interface'));
    failures = failures + assert_ok('1  a tag the Synapse module lacks is skipped by name', ...
        contains(out, '"Shape"') && contains(out, 'not found'));
    failures = failures + assert_ok('1  the crossing is reported once, with the count', ...
        numel(strfind(out, 'TDT_RPcox -> TDT_Synapse')) == 1 && contains(out, '3 parameter(s)'));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 1: %s (%s line %d)\n', ME.message, ME.stack(1).name, ME.stack(1).line);
end

%% 2. Synapse phase -> RPcox session (the reverse)
try
    syn.find_parameter('TimeoutDur').Value = 250;
    synapsePhase = fullfile(tmpDir, 'synapse_phase.eprot');
    PB.save(synapsePhase);

    rp.RunOffline = true; % no RPco.x here; Runtime.Interfaces then leaves it unconnected
    R2 = epsych.Runtime;
    R2.isTest = true;
    R2.EVENTS = epsych.EventHub;
    R2.Interfaces = PA.Interfaces;
    R2.Protocol = PA;

    out = evalc('R2.readParameters(synapsePhase);');
    failures = failures + assert_ok('2  tags saved under TDT_Synapse land on the TDT_RPcox module', ...
        rp.find_parameter('TimeoutDur').Value == 250 && ~contains(out, 'No matching interface'));
    failures = failures + assert_ok('2  reported as the reverse crossing', ...
        contains(out, 'TDT_Synapse -> TDT_RPcox'));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 2: %s (%s line %d)\n', ME.message, ME.stack(1).name, ME.stack(1).line);
end

%% 3. A type outside the group still finds nothing
try
    foreignPhase = fullfile(tmpDir, 'foreign_phase.eprot');
    raw = builtin('load', rpcoxPhase, '-mat');
    for i = 1:numel(raw.protocol.InterfaceData)
        if strcmp(raw.protocol.InterfaceData{i}.Type, 'TDT_RPcox')
            raw.protocol.InterfaceData{i}.Type = 'Intan_RHX';
        end
    end
    protocol = raw.protocol;
    builtin('save', foreignPhase, 'protocol', '-mat');

    api.clearLog();
    out = evalc('R.readParameters(foreignPhase);');
    failures = failures + assert_ok('3  an Intan_RHX entry is skipped in a session with no Intan interface', ...
        contains(out, 'No matching interface') && contains(out, 'Intan_RHX') && api.callCount('setParameterValue') == 0);
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 3: %s (%s line %d)\n', ME.message, ME.stack(1).name, ME.stack(1).line);
end

%% 4. An exact-type interface is always preferred to a fallback
try
    % A session holding BOTH backends: the RPcox phase must go to RPcox.
    PC = epsych.Protocol(Name = 'BothSides', Info = 'phase fallback');
    rp2 = hw.TDT_RPcox({}, {}, {}, Connect = false);
    MC = hw.Module(rp2, 'RZ6', 'Behavior', uint8(1));
    rp2.setModules(MC);
    add_with_value(MC, 'TimeoutDur', 1, 'Float');
    rp2.RunOffline = true;
    PC.addInterface(rp2);
    api2 = SynapseAPI_Mock(Experiment = circuit, Rates = rates);
    syn2 = TDT_Synapse_Mock(api2);
    MD = hw.Module(syn2, 'RZ6(1)', 'Behavior', uint8(1));
    syn2.setModules(MD);
    add_with_value(MD, 'TimeoutDur', 2, 'Float');
    PC.addInterface(syn2);

    R3 = epsych.Runtime;
    R3.isTest = true;
    R3.EVENTS = epsych.EventHub;
    R3.Interfaces = PC.Interfaces;
    R3.Protocol = PC;
    api2.clearLog();
    out = evalc('R3.readParameters(rpcoxPhase);');
    failures = failures + assert_ok('4  with an RPcox interface present the RPcox entry goes there only', ...
        rp2.find_parameter('TimeoutDur').Value == 100 && api2.callCount('setParameterValue') == 0 && ...
        ~contains(out, '->'));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  group 4: %s (%s line %d)\n', ME.message, ME.stack(1).name, ME.stack(1).line);
end

%% Summary
fprintf('\n=== %s: %d failure(s) ===\n', mfilename, failures);
if failures > 0
    error('smoke_test_phase_parent_type_fallback:failed', '%d assertion(s) failed.', failures);
end


function p = add_with_value(module, name, value, type)
    % add_parameter fills the design-time Values list; a phase records Value.
    p = module.add_parameter(name, value, Type = type);
    p.Value = value;
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
