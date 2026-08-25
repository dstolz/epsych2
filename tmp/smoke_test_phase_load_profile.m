function smoke_test_phase_load_profile()
% smoke_test_phase_load_profile()
% Measure where phase-load time actually goes, so the optimization work is
% aimed at the layer that costs the most rather than at the one that looks
% expensive. Builds a synthetic phase scaled to a real rig, then times each
% layer of the load path separately and profiles one full preview+load cycle.
%
% Not a pass/fail test -- it reports timings. It fails only if the harness
% itself breaks, so it can still be run unattended after each change.
%
%   matlab -batch "run('tmp/smoke_test_phase_load_profile.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

NPARAMS = 120;   % scaled to a real rig
NEXPR   = 15;    % expression-bearing subset
NREPS   = 3;     % repetitions per timed layer

tmpDir = fullfile(tempdir, 'epsych_smoke_phase_profile');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% gui.components.PhaseSelector prefers its remembered directory (setpref) over the
% constructor argument, so an operator's real phase directory would otherwise
% hijack the cycle timed in section 3.
prefGroup = 'epsych2_gui_PhaseSelector';
prefKey   = 'LastPhasePath';
if ispref(prefGroup, prefKey)
    savedPhasePref = getpref(prefGroup, prefKey);
    cleanupPref = onCleanup(@() setpref(prefGroup, prefKey, savedPhasePref));
else
    cleanupPref = onCleanup(@() rmprefIfSet(prefGroup, prefKey));
end
rmprefIfSet(prefGroup, prefKey);

% ===== Setup: a phase scaled to a real rig ==============================
[P, R] = buildProtocol(NPARAMS, NEXPR);
phaseFile = fullfile(tmpDir, 'profilePhase.eprot');
R.writeParametersProtocol(phaseFile, "Profile phase");

d = dir(phaseFile);
fprintf('\nPhase file: %d parameters (%d with expressions), %.1f kB\n\n', ...
    numel(R.all_parameters(includeInvisible=true)), NEXPR, d(1).bytes/1024);

% ===== 1. Time each layer separately ====================================
% Each layer subsumes the ones above it, so the incremental column is what
% attributes cost. Caching, if present, is bypassed so this keeps reporting
% the cold cost of a parse after the cache lands.
try
    % Visible='on' because loadPhaseParameters opens a uiprogressdlg, which
    % refuses to attach to a hidden figure. Under -batch there is no display,
    % so nothing is actually drawn.
    fig = uifigure('Visible', 'on');
    cleanupFig = onCleanup(@() delete(fig));
    ps = gui.components.PhaseSelector(R, tmpDir);
    h  = ps.createGUI(uipanel(fig));
    h.PhaseSelect.Value = 'profilePhase';

    % showPhaseInfo is the public entry to the private
    % computePhaseChanges -> resolvePhaseAgainstRuntime pair; the table
    % formatting it adds is negligible next to the parse.
    layers = { ...
        'Protocol.load',              @() epsych.Protocol.load(char(phaseFile)); ...
        'phaseParameterData',         @() phaseParameterDataNoCache(phaseFile); ...
        'preview (resolve + table)',  @() ps.showPhaseInfo([]); ...
        'readParameters',             @() R.readParameters(phaseFile); ...
        'updateTrialsFromParameters', @() R.updateTrialsFromParameters(R.all_parameters()) };

    t = zeros(size(layers,1), 1);
    for k = 1:size(layers,1)
        fcn = layers{k,2};
        best = inf;
        for rep = 1:NREPS
            clearPhaseCacheIfPresent();
            tic; evalc('fcn()'); best = min(best, toc);   % evalc: silence the layer's own logging
        end
        t(k) = best;
    end

    total = t(end-1);   % readParameters is the full parse+resolve+apply path
    fprintf('%-30s %10s %10s\n', 'layer (best of 3)', 'seconds', '%% of load');
    fprintf('%s\n', repmat('-', 1, 52));
    for k = 1:numel(t)
        fprintf('%-30s %10.3f %9.0f%%\n', layers{k,1}, t(k), 100*t(k)/total);
    end
    fprintf('\n');

    fprintf('PASS: 1. per-layer timing\n');
catch ME
    failures{end+1} = sprintf('1. per-layer timing: %s', ME.message);
    fprintf('FAIL: 1. %s\n', ME.message);
end

% ===== 2. Count parses per preview+load cycle ===========================
% The headline symptom: one preview plus one Load currently parses the same
% file three times. Counted from Protocol.load's own banner so it works
% before any instrumentation exists.
try
    clearPhaseCacheIfPresent();
    h.PhaseSelect.Value = 'profilePhase';
    out = evalc('ps.onPhaseSelectionChanged(h.PhaseSelect); ps.loadPhaseParameters([]);');
    nLoads = numel(strfind(out, '[INFO] Protocol loaded from:'));
    fprintf('Protocol.load invocations per preview+load cycle: %d\n\n', nLoads);
    fprintf('PASS: 2. parse count\n');
catch ME
    failures{end+1} = sprintf('2. parse count: %s', ME.message);
    fprintf('FAIL: 2. %s\n', ME.message);
end

% ===== 3. Profile one full cycle ========================================
% Attributes the residual (dbstack in the logger, find_parameter, set.Value,
% ...) instead of guessing at it. -batch supports the profiler.
try
    clearPhaseCacheIfPresent();
    profile off; profile clear; profile on;
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect); ps.loadPhaseParameters([]);');
    profile off;

    pinfo = profile('info');
    [~, ord] = sort([pinfo.FunctionTable.TotalTime], 'descend');
    n = min(15, numel(ord));
    fprintf('%-46s %8s %8s\n', 'function', 'calls', 'total s');
    fprintf('%s\n', repmat('-', 1, 64));
    for k = 1:n
        f = pinfo.FunctionTable(ord(k));
        fprintf('%-46s %8d %8.3f\n', truncate(f.FunctionName, 46), f.NumCalls, f.TotalTime);
    end
    fprintf('\n');

    fprintf('PASS: 3. profile of one preview+load cycle\n');
catch ME
    failures{end+1} = sprintf('3. profile: %s', ME.message);
    fprintf('FAIL: 3. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_phase_load_profile: ALL PASS\n');
else
    fprintf('\nsmoke_test_phase_load_profile: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_phase_load_profile:failed', '%d failure(s)', numel(failures));
end

end


function [P, R] = buildProtocol(nParams, nExpr)
% Build a protocol whose parameter mix matches a working rig: mostly plain
% scalars, a roved multi-level parameter, expression-bearing parameters that
% force the fixed-point restore loop, a trigger, and an operator toggle.
P = epsych.Protocol(Name='ProfileTest', Info='Phase load profiling');

P.addParameter('Software', 'StimDelay', 2021, Type='Float');
P.addParameter('Software', 'StimDur',   1000, Type='Float');
P.addParameter('Software', 'Lvl', [10 20 30 40 50], Type='Float');   % roved
P.addParameter('Software', 'TrialType', [0 1], Type='Integer');
P.addParameter('Software', 'DeliverTrials', false, Type='Boolean');  % operator toggle

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

pDeliver = sw.find_parameter('DeliverTrials');
pDeliver.UpdateEveryTrial = false;

% Expression-bearing parameters chain off StimDelay, so localRestoreValues
% cannot settle them in a single pass -- the case that makes a load slow.
for k = 1:nExpr
    name = sprintf('Derived%02d', k);
    P.addParameter('Software', name, 0, Type='Float');
    p = sw.find_parameter(name);
    p.Expression = sprintf('StimDelay + %d', k);
end

% Pad out to the target count with plain scalars.
nPlain = nParams - numel(sw.all_parameters(includeInvisible=true));
for k = 1:max(0, nPlain)
    P.addParameter('Software', sprintf('Plain%03d', k), k, Type='Float');
end

R = epsych.Runtime;
R.Interfaces = P.Interfaces;   % same handles: live values reside in the protocol
R.Protocol = P;
end


function paramData = phaseParameterDataNoCache(filepath)
% Call phaseParameterData with caching off once that option exists, so this
% harness keeps reporting the cold parse cost after the cache lands.
try
    paramData = epsych.Runtime.phaseParameterData(filepath, UseCache=false);
catch
    paramData = epsych.Runtime.phaseParameterData(filepath);
end
end


function clearPhaseCacheIfPresent()
% No-op until the phase cache exists, so this harness runs against both the
% pre- and post-optimization code.
if ismember('phaseCache', methods('epsych.Runtime'))
    epsych.Runtime.phaseCache('clear');
end
end


function s = truncate(s, n)
if numel(s) > n, s = ['...' s(end-n+4:end)]; end
end


function rmprefIfSet(group, key)
% Remove a preference only if it exists; rmpref errors on a missing key.
if ispref(group, key)
    rmpref(group, key);
end
end
