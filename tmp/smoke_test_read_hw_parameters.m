% smoke_test_read_hw_parameters.m
% Smoke tests for hw.Interface.canReadHardwareParameters /
% readHardwareParameters and the TDT backend overrides.
%
% No TDT hardware required: the TDT_RPcox path reads the RPvds circuit file
% through the RPco.X COM server (ReadCOF) when the TDT drivers are
% installed, and degrades gracefully when they are not. The TDT_Synapse test
% only asserts the no-throw contract, tolerating both a live local Synapse
% and none at all.
%
% Run headless:
%   matlab -batch "run('tmp/smoke_test_read_hw_parameters.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('epsych_startup'))
    addpath(repoRoot);
end
if isempty(which('hw.Module'))
    epsych_startup
end

fprintf('\n=== readHardwareParameters Smoke Test ===\n\n');

failures = 0;

%% 1. Base-class default declines (hw.Software)
try
    sw = hw.Software();
    m = sw.Module(1);
    failures = failures + assert_ok('Software: canReadHardwareParameters is false', ...
        ~sw.canReadHardwareParameters(m));
    [tf, msg] = sw.readHardwareParameters(m);
    failures = failures + assert_ok('Software: readHardwareParameters declines without throwing', ...
        ~tf && contains(msg, 'does not support'));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  Software default: %s\n', ME.message);
end

%% 2. TDT_RPcox offline: capability + missing-file edge cases
rcx = fullfile(repoRoot, 'examples', 'stimgen', 'StimGenCircuit.rcx');
try
    iface = hw.TDT_RPcox({}, {}, {}, Interface='GB', Connect=false);

    mGood = hw.Module(iface, 'RZ6', 'SmokeTest', uint8(1));
    mGood.Info.RPvdsFile = rcx;
    mNoFile = hw.Module(iface, 'RZ6', 'NoFile', uint8(2));
    mBadFile = hw.Module(iface, 'RZ6', 'BadFile', uint8(3));
    mBadFile.Info.RPvdsFile = fullfile(repoRoot, 'does_not_exist.rcx');
    iface.setModules([mGood, mNoFile, mBadFile]);

    failures = failures + assert_ok('RPcox: canRead true with RPvdsFile configured', ...
        iface.canReadHardwareParameters(mGood));
    failures = failures + assert_ok('RPcox: canRead false without RPvdsFile', ...
        ~iface.canReadHardwareParameters(mNoFile));

    [tf, msg] = iface.readHardwareParameters(mNoFile);
    failures = failures + assert_ok('RPcox: no RPvdsFile declines gracefully', ...
        ~tf && contains(msg, 'no RPvds circuit file'));

    [tf, msg] = iface.readHardwareParameters(mBadFile);
    failures = failures + assert_ok('RPcox: missing file declines gracefully', ...
        ~tf && contains(msg, 'not found'));

    % Foreign module rejected
    other = hw.TDT_RPcox({}, {}, {}, Interface='GB', Connect=false);
    mForeign = hw.Module(other, 'RZ6', 'Foreign', uint8(1));
    other.setModules(mForeign);
    [tf, msg] = iface.readHardwareParameters(mForeign);
    failures = failures + assert_ok('RPcox: foreign module rejected', ...
        ~tf && contains(msg, 'does not belong'));
catch ME
    failures = failures + 1;
    fprintf('  FAIL  RPcox offline setup: %s\n', ME.message);
end

%% 3. TDT_RPcox offline discovery via ReadCOF (needs RPco.x ActiveX, not hardware)
try
    [tf, msg] = iface.readHardwareParameters(mGood);
    if tf
        n1 = numel(mGood.Parameters);
        failures = failures + assert_ok('RPcox: offline discovery found parameters', n1 > 0);
        failures = failures + assert_ok('RPcox: no invalid ''Logical'' types', ...
            ~any(strcmp({mGood.Parameters.Type}, 'Logical')));
        failures = failures + assert_ok('RPcox: hardware names recorded', ...
            all(arrayfun(@(p) ~isempty(hw.Interface.getHardwareParameterName(p)), mGood.Parameters)));

        % Merge is idempotent
        [tf2, msg2] = iface.readHardwareParameters(mGood);
        failures = failures + assert_ok('RPcox: repeat merge adds nothing', ...
            tf2 && numel(mGood.Parameters) == n1 && contains(msg2, 'added 0'));

        % Replace rebuilds the same list
        [tf3, ~] = iface.readHardwareParameters(mGood, Mode='replace');
        failures = failures + assert_ok('RPcox: replace rebuilds full list', ...
            tf3 && numel(mGood.Parameters) == n1);

        fprintf('        (%s)\n', msg);
    else
        % RPco.x ActiveX not installed on this machine — graceful decline is
        % the correct behavior; discovery assertions are skipped.
        failures = failures + assert_ok('RPcox: ReadCOF unavailable declines gracefully', ...
            ~isempty(msg));
        fprintf('        SKIP discovery assertions: %s\n', msg);
    end
catch ME
    failures = failures + 1;
    fprintf('  FAIL  RPcox offline discovery: %s\n', ME.message);
end

%% 4. TDT_Synapse: capability + no-throw contract
try
    syn = hw.TDT_Synapse('localhost', Connect=false);
    mSyn = hw.Module(syn, 'RZ2(1)', 'RZ2', uint8(1));
    syn.setModules(mSyn);

    failures = failures + assert_ok('Synapse: canReadHardwareParameters is true', ...
        syn.canReadHardwareParameters(mSyn));

    [tf, msg] = syn.readHardwareParameters(mSyn);
    failures = failures + assert_ok('Synapse: readHardwareParameters returns without throwing', ...
        islogical(tf) || ismember(tf, [0 1]));
    if tf
        fprintf('        live Synapse responded: %s\n', msg);
    else
        fprintf('        no live Synapse (expected on most machines): %s\n', msg);
    end
catch ME
    failures = failures + 1;
    fprintf('  FAIL  Synapse: %s\n', ME.message);
end

%% Summary
fprintf('\n=== %s: %d failure(s) ===\n', mfilename, failures);
if failures > 0
    error('smoke_test_read_hw_parameters:failed', '%d assertion(s) failed.', failures);
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
