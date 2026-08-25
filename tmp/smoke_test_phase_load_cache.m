function smoke_test_phase_load_cache()
% smoke_test_phase_load_cache()
% Gate on the phase parse cache (epsych.Runtime.phaseCache): one preview plus
% one Load must parse the phase file exactly once, the cached parse must apply
% exactly the state a cold parse would, and re-saving a phase mid-session must
% not serve the stale parse.
%
% The equivalence check is a self-contained A/B rather than a checked-in golden
% file: the same cycle runs twice from an identical starting state, once with
% the cache disabled (which reproduces the pre-cache behavior) and once warm.
% That keeps proving equivalence as the surrounding code changes.
%
%   matlab -batch "run('tmp/smoke_test_phase_load_cache.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_phase_cache');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% gui.components.PhaseSelector prefers its remembered directory (setpref) over the
% constructor argument, so an operator's real phase directory would hijack this.
prefGroup = 'epsych2_gui_PhaseSelector';
prefKey   = 'LastPhasePath';
if ispref(prefGroup, prefKey)
    savedPhasePref = getpref(prefGroup, prefKey);
    cleanupPref = onCleanup(@() setpref(prefGroup, prefKey, savedPhasePref));
else
    cleanupPref = onCleanup(@() rmprefIfSet(prefGroup, prefKey));
end
rmprefIfSet(prefGroup, prefKey);

cleanupCache = onCleanup(@() epsych.Runtime.phaseCache('enable'));

% ===== Setup ============================================================
% Parameters covering the branches a phase load takes: an expression, a roved
% list, a trigger, and an operator toggle (whose value the load must leave
% alone), alongside plain scalars.
P = epsych.Protocol(Name='CacheTest', Info='Phase cache');
P.addParameter('Software', 'StimDelay', 2021, Type='Float');
P.addParameter('Software', 'Lvl', [10 20 30], Type='Float');
P.addParameter('Software', 'RespWinDelay', 0, Type='Float');
P.addParameter('Software', 'DeliverTrials', false, Type='Boolean');
P.addParameter('Software', 'TrialType', [0 1], Type='Integer');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);
sw.find_parameter('RespWinDelay').Expression = 'StimDelay + 100';
sw.find_parameter('DeliverTrials').UpdateEveryTrial = false;

R = epsych.Runtime;
R.Interfaces = P.Interfaces;   % same handles: live values reside in the protocol
R.Protocol = P;

pLevel = R.find_parameter('Lvl');
pDelay = R.find_parameter('StimDelay');
pLevel.Value = 20;
pDelay.Value = 2021;

phaseFile = fullfile(tmpDir, 'phaseCache.eprot');
R.writeParametersProtocol(phaseFile, "Cache phase");

fig = uifigure('Visible', 'on');   % uiprogressdlg refuses a hidden figure
cleanupFig = onCleanup(@() delete(fig));
ps = gui.components.PhaseSelector(R, tmpDir);
h  = ps.createGUI(uipanel(fig));
h.PhaseSelect.Value = 'phaseCache';


% ===== A. One preview plus one Load parses the file once =================
try
    epsych.Runtime.phaseCache('enable');
    epsych.Runtime.phaseCache('clear');
    epsych.Runtime.phaseCache('resetstats');

    out = runCycle(ps, h);

    st = epsych.Runtime.phaseCache('stats');
    assert(st.Parses == 1, 'expected 1 parse per preview+load cycle, got %d', st.Parses);
    assert(st.Hits >= 2, 'expected the preview parse to be reused twice, got %d hits', st.Hits);

    % Belt and braces against the counter itself being wrong: Protocol.load's
    % own banner must not appear more than once either. (It appears zero times
    % when the fast parse handles the file, which is the normal case.)
    assert(numel(strfind(out, '[INFO] Protocol loaded from:')) <= 1, ...
        'Protocol.load ran more than once during a single cycle');

    % Selecting the same phase again must not re-read the file.
    before = epsych.Runtime.phaseCache('stats');
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');
    after = epsych.Runtime.phaseCache('stats');
    assert(after.Parses == before.Parses, 'browsing a cached phase re-parsed it');

    fprintf('PASS: A. one preview+load cycle parses the phase file once\n');
catch ME
    failures{end+1} = sprintf('A. parse count: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. A cached load applies exactly what a cold load applies =========
try
    restoreState(R);
    baseline = snapshot(R);

    epsych.Runtime.phaseCache('disable');   % reproduces the pre-cache behavior
    restoreState(R);
    runCycle(ps, h);
    cold = snapshot(R);

    epsych.Runtime.phaseCache('enable');
    epsych.Runtime.phaseCache('clear');
    restoreState(R);
    runCycle(ps, h);
    warm = snapshot(R);

    assert(~isequaln(cold, baseline), ...
        'the load changed nothing, so this comparison proves nothing');
    assert(numel(cold) == numel(warm), 'parameter count changed between cycles');
    for k = 1:numel(cold)
        a = warm{k}; b = cold{k};
        a.lastUpdated = 0; b.lastUpdated = 0;   % wall-clock stamp, not state
        assert(isequaln(a, b), 'parameter "%s" differs between cold and warm load', a.Name);
    end

    fprintf('PASS: B. cached and uncached loads leave identical state\n');
catch ME
    failures{end+1} = sprintf('B. cold/warm equivalence: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Re-saving a phase invalidates its cached parse =================
try
    epsych.Runtime.phaseCache('enable');
    epsych.Runtime.phaseCache('clear');

    R.readParameters(phaseFile);            % populate the cache
    assert(isequal(pLevel.Value, 20), 'setup: phase should restore Lvl to 20');

    pLevel.Value = 55;
    R.writeParametersProtocol(phaseFile, "Cache phase v2");
    pLevel.Value = 10;
    R.readParameters(phaseFile);
    assert(isequal(pLevel.Value, 55), ...
        'stale cache: the re-saved phase did not take effect (got %s)', mat2str(pLevel.Value));

    % And the same via mtime alone, with the explicit invalidation bypassed:
    % a phase file rewritten by something other than writeParametersProtocol
    % (ProtocolDesigner, a copy) must still be noticed.
    F = load(phaseFile, '-mat');
    protocol = F.protocol;
    for i = 1:numel(protocol.InterfaceData)
        for m = 1:numel(protocol.InterfaceData{i}.Modules)
            pp = protocol.InterfaceData{i}.Modules{m}.Parameters;
            for j = 1:numel(pp)
                if strcmp(pp{j}.Name, 'Lvl')
                    pp{j}.Value = 77; pp{j}.Values = {77};
                end
            end
            protocol.InterfaceData{i}.Modules{m}.Parameters = pp;
        end
    end
    pause(1.1);   % ensure a distinct modification timestamp
    save(phaseFile, 'protocol', '-mat');
    pLevel.Value = 10;
    R.readParameters(phaseFile);
    assert(isequal(pLevel.Value, 77), ...
        'stale cache: an external rewrite was not noticed (got %s)', mat2str(pLevel.Value));

    fprintf('PASS: C. a re-saved phase is re-parsed\n');
catch ME
    failures{end+1} = sprintf('C. invalidation: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Eviction and the escape hatches ===============================
try
    epsych.Runtime.phaseCache('enable');
    epsych.Runtime.phaseCache('clear');

    % More distinct phases than the cache holds: it must stay bounded and keep
    % answering correctly, not grow without limit.
    many = strings(0,1);
    for k = 1:12
        f = fullfile(tmpDir, sprintf('bulk%02d.eprot', k));
        pLevel.Value = k;
        R.writeParametersProtocol(f, sprintf("Bulk %d", k));
        many(end+1,1) = string(f); %#ok<AGROW>
    end
    for f = reshape(many, 1, [])
        epsych.Runtime.phaseParameterData(f);
    end
    st = epsych.Runtime.phaseCache('stats');
    assert(st.Entries <= 8, 'cache grew to %d entries', st.Entries);

    % The most recent phases are still served without re-reading.
    before = epsych.Runtime.phaseCache('stats');
    epsych.Runtime.phaseParameterData(many(end));
    after = epsych.Runtime.phaseCache('stats');
    assert(after.Parses == before.Parses, 'the most recent phase was evicted');

    epsych.Runtime.phaseCache('clear');
    assert(epsych.Runtime.phaseCache('stats').Entries == 0, 'clear left entries behind');

    epsych.Runtime.phaseCache('disable');
    epsych.Runtime.phaseParameterData(many(end));
    assert(epsych.Runtime.phaseCache('stats').Entries == 0, 'disabled cache still stored');
    epsych.Runtime.phaseCache('enable');

    threw = false;
    try
        epsych.Runtime.phaseCache('nonsense');
    catch guardME
        threw = strcmp(guardME.identifier, 'epsych:Runtime:phaseCache:UnknownAction');
    end
    assert(threw, 'an unknown action should raise epsych:Runtime:phaseCache:UnknownAction');

    fprintf('PASS: D. the cache stays bounded and the escape hatches work\n');
catch ME
    failures{end+1} = sprintf('D. eviction/escape hatches: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_phase_load_cache: ALL PASS\n');
else
    fprintf('\nsmoke_test_phase_load_cache: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_phase_load_cache:failed', '%d failure(s)', numel(failures));
end

end


function out = runCycle(ps, h)
% One operator cycle: select the phase (which previews it), then press Load.
out = evalc('ps.onPhaseSelectionChanged(h.PhaseSelect); ps.loadPhaseParameters([]);');
end


function S = snapshot(R)
S = arrayfun(@(p) p.toStruct(), R.all_parameters(includeInvisible=true), 'UniformOutput', false);
end


function restoreState(R)
% Put the live parameters back to a fixed pre-load state so each cycle starts
% from the same place and the load has something to change.
R.find_parameter('Lvl').Value = 30;
R.find_parameter('StimDelay').Value = 1;
R.find_parameter('DeliverTrials').Value = true;
end


function rmprefIfSet(group, key)
% Remove a preference only if it exists; rmpref errors on a missing key.
if ispref(group, key)
    rmpref(group, key);
end
end
