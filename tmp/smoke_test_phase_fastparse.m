function smoke_test_phase_fastparse()
% smoke_test_phase_fastparse()
% Gate on epsych.Runtime.phaseParameterData's fast parse: reading the saved
% parameter structs directly out of an .eprot must be indistinguishable from
% reconstructing an epsych.Protocol and re-serializing it.
%
% Checked two ways, because struct-level equality alone would not prove the
% difference is harmless: entry-by-entry against the fallback parse, and
% end-to-end by running a full preview+load cycle under each setting and
% comparing the state it leaves behind.
%
%   matlab -batch "run('tmp/smoke_test_phase_fastparse.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
repoRoot = fileparts(here);

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_phase_fastparse');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% gui.components.PhaseSelector prefers its remembered directory (setpref) over the
% constructor argument, so an operator's real phase directory would hijack
% section C.
prefGroup = 'epsych2_gui_PhaseSelector';
prefKey   = 'LastPhasePath';
if ispref(prefGroup, prefKey)
    savedPhasePref = getpref(prefGroup, prefKey);
    cleanupPref = onCleanup(@() setpref(prefGroup, prefKey, savedPhasePref));
else
    cleanupPref = onCleanup(@() rmprefIfSet(prefGroup, prefKey));
end
rmprefIfSet(prefGroup, prefKey);

% ===== Fixtures =========================================================
% A protocol whose parameters cover every branch the two parse paths could
% diverge on: expressions (re-evaluated by the fallback), a random parameter
% (re-drawn), a roved list, a clamped value, a trigger, an operator toggle,
% and a StimType carrying stimgen objects.
[P, R, pLevel] = buildProtocol();
fixtureFile = fullfile(tmpDir, 'fixture.eprot');
R.writeParametersProtocol(fixtureFile, "Fast parse fixture");

jsonFile = fullfile(tmpDir, 'legacy.json');
R.writeParametersJSON(jsonFile, "Legacy JSON phase");

% Every protocol file checked into the repo, so a shape nobody remembers
% writing is still covered.
repoFiles = [ ...
    dirFiles(fullfile(repoRoot, 'tmp'), '*.eprot'); ...
    dirFiles(fullfile(repoRoot, 'tmp'), '*.prot'); ...
    dirFiles(fullfile(repoRoot, 'examples'), '**/*.eprot'); ...
    dirFiles(fullfile(repoRoot, 'examples'), '**/*.prot')];

files = [string(fixtureFile); repoFiles];

% ===== A. Fast and fallback parses agree entry by entry ==================
nFast = 0; nFallback = 0; nSkipped = 0;
try
    for f = reshape(files, 1, [])
        % A repo file the fallback itself cannot read is not this change's
        % problem; it is reported and skipped rather than masked as a failure.
        try
            engaged = usedFastParse(f);
        catch parseME
            nSkipped = nSkipped + 1;
            fprintf('      skipped %s (%s)\n', f, parseME.message);
            continue
        end

        % When the gate refused the file, both settings run the same code and
        % comparing them would prove nothing -- worse, it would fail on
        % Protocol.load's own nondeterminism (a file missing a meta field keeps
        % the constructor's datetime('now')). Count it and move on.
        if ~engaged
            nFallback = nFallback + 1;
            continue
        end
        nFast = nFast + 1;

        [fastPD, fastMD] = epsych.Runtime.phaseParameterData(f, UseCache=false, FastParse=true);
        [fullPD, fullMD] = epsych.Runtime.phaseParameterData(f, UseCache=false, FastParse=false);

        assert(numel(fastPD) == numel(fullPD), ...
            '%s: %d entries fast vs %d fallback', f, numel(fastPD), numel(fullPD));
        if ~isempty(fullPD)
            assert(isequal(fieldnames(fastPD), fieldnames(fullPD)), ...
                '%s: field names or order differ', f);
        end
        assert(isequaln(fastMD, fullMD), '%s: metadata differs', f);

        for k = 1:numel(fullPD)
            a = fastPD(k); b = fullPD(k);
            assert(strcmp(a.Name, b.Name), '%s: entry %d name mismatch', f, k);

            % The analyzed divergences, each harmless because every consumer
            % re-derives the field from the live parameter or overwrites it.
            % Nothing else may differ.
            a.lastUpdated = 0; b.lastUpdated = 0;
            a.Access = normAccess(a.Access); b.Access = normAccess(b.Access);
            if strlength(string(b.Expression)) > 0 || b.isRandom
                a.Value = []; b.Value = [];
            end
            % One-way parameters cannot round-trip Value through live
            % objects: fromStruct never restores a Read parameter's Value
            % (it stays empty until hardware provides one), and a Write
            % parameter's get.Value returns NaN, whose restore re-derives
            % isArray from that scalar. The fast path keeps what the file
            % recorded in both cases. Consumers never use the entry's Value
            % for either access mode, so the divergence is harmless (and
            % the fast path is the more faithful of the two).
            if ismember(char(string(b.Access)), {'Read', 'Write'})
                a.Value = []; b.Value = [];
                a.isArray = false; b.isArray = false;
            end

            assert(isequaln(a, b), '%s: entry "%s" differs between parses', f, a.Name);
        end
    end
    fprintf('PASS: A. fast and fallback parses agree (%d fast, %d fell back, %d skipped, %d files)\n', ...
        nFast, nFallback, nSkipped, numel(files));
    assert(nFast > 0, 'the fast path never engaged; section A proved nothing');
catch ME
    failures{end+1} = sprintf('A. differential parse: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Shapes the fast path must refuse ==============================
try
    % Legacy JSON is not a protocol file at all: it must still parse, via the
    % JSON branch, untouched by any of this.
    [jd, jmd] = epsych.Runtime.phaseParameterData(jsonFile, UseCache=false);
    assert(jmd.Source == "JSON" && ~isempty(jd), 'legacy JSON phase should still parse');

    % A future format revision must fall back rather than be guessed at.
    bumped = fullfile(tmpDir, 'bumped.eprot');
    F = load(fixtureFile, '-mat');
    protocol = F.protocol;
    protocol.formatVersion = 2.0;
    save(bumped, 'protocol', '-mat');
    assert(~usedFastParse(bumped), 'a bumped formatVersion must fall back');

    % A file missing a toStruct field must fall back rather than emit a short entry.
    trimmed = fullfile(tmpDir, 'trimmed.eprot');
    protocol = F.protocol;
    protocol.InterfaceData{1}.Modules{1}.Parameters{1} = ...
        rmfield(protocol.InterfaceData{1}.Modules{1}.Parameters{1}, 'Expression');
    save(trimmed, 'protocol', '-mat');
    assert(~usedFastParse(trimmed), 'a missing toStruct field must fall back');

    % Interfaces recoverable only from COMPILED.writeparams must fall back.
    recovered = fullfile(tmpDir, 'recovered.eprot');
    protocol = F.protocol;
    protocol.InterfaceData = {};
    save(recovered, 'protocol', '-mat');
    assert(~usedFastParse(recovered), 'an empty InterfaceData must fall back');

    fprintf('PASS: B. unrecognized shapes fall back to Protocol.load\n');
catch ME
    failures{end+1} = sprintf('B. fallback gates: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. A full load cycle leaves identical state =======================
% What actually matters: not that the parses match field for field, but that
% loading a phase applies the same thing either way.
try
    fig = uifigure('Visible', 'on');   % uiprogressdlg refuses a hidden figure
    cleanupFig = onCleanup(@() delete(fig));
    ps = gui.components.PhaseSelector(R, tmpDir);
    h  = ps.createGUI(uipanel(fig));
    h.PhaseSelect.Value = 'fixture';

    baseline = snapshot(R);

    % The GUI has no FastParse argument, so the fallback cycle is driven by
    % priming the phase cache with a fallback parse: every consumer in the
    % cycle then reads that instead of parsing for itself.
    restoreState(R, pLevel);
    epsych.Runtime.phaseCache('clear');
    [pd, md] = epsych.Runtime.phaseParameterData(string(fixtureFile), ...
        UseCache=false, FastParse=false);
    epsych.Runtime.phaseCache('put', string(fixtureFile), ...
        struct('paramData', pd, 'metadata', md));
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect); ps.loadPhaseParameters([]);');
    slow = snapshot(R);

    restoreState(R, pLevel);
    epsych.Runtime.phaseCache('clear');
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect); ps.loadPhaseParameters([]);');
    fast = snapshot(R);

    assert(numel(slow) == numel(fast), 'parameter count changed between cycles');
    for k = 1:numel(slow)
        a = fast{k}; b = slow{k};
        a.lastUpdated = 0; b.lastUpdated = 0;
        if a.isRandom, a.Value = []; b.Value = []; end
        assert(isequaln(a, b), 'parameter "%s" differs after fast vs fallback load', a.Name);
    end
    assert(~isequaln(slow, baseline), ...
        'the load changed nothing, so this comparison proves nothing');

    fprintf('PASS: C. a full load cycle applies identical state either way\n');
catch ME
    failures{end+1} = sprintf('C. end-to-end equivalence: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_phase_fastparse: ALL PASS\n');
else
    fprintf('\nsmoke_test_phase_fastparse: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_phase_fastparse:failed', '%d failure(s)', numel(failures));
end

end


function [P, R, pLevel] = buildProtocol()
% Cover every branch the two parse paths could diverge on.
P = epsych.Protocol(Name='FastParseTest', Info='Fast parse fixture');
P.addParameter('Software', 'StimDelay', 2021, Type='Float');
P.addParameter('Software', 'Lvl', [10 20 30 40], Type='Float');       % roved
P.addParameter('Software', 'Bounded', 5, Type='Float');               % clamped
P.addParameter('Software', 'Jitter', [1 2 3], Type='Float');          % randomized
P.addParameter('Software', 'RespWinDelay', 0, Type='Float');          % expression
P.addParameter('Software', 'DeliverTrials', false, Type='Boolean');   % operator toggle
P.addParameter('Software', 'RepeatOnAbort', false, Type='Boolean');   % genuine setting
P.addParameter('Software', 'TrialType', [0 1], Type='Integer');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

pBounded = sw.find_parameter('Bounded');
pBounded.Min = 0; pBounded.Max = 10;

pJitter = sw.find_parameter('Jitter');
pJitter.Min = 1; pJitter.Max = 3;   % isRandom requires finite bounds
pJitter.isRandom = true;

pDelay = sw.find_parameter('RespWinDelay');
pDelay.Expression = 'StimDelay + 100';

pDeliver = sw.find_parameter('DeliverTrials');
pDeliver.UpdateEveryTrial = false;
pDeliver.Value = true;   % operator switched it on; the phase must not carry this

% A StimType parameter exercises the struct -> stimgen object -> struct round
% trip the fast path skips. Guarded: the stimgen submodule may be absent.
try
    sw.add_parameter('Stim', stimgen.Tone, Type='StimType');
catch ME
    vprintf(1, 'StimType fixture skipped: %s', ME.message)
end

R = epsych.Runtime;
R.Interfaces = P.Interfaces;   % same handles: live values reside in the protocol
R.Protocol = P;

pLevel = sw.find_parameter('Lvl');
pLevel.Value = 20;
end


function tf = usedFastParse(filepath)
% True when the fast path handled the file. Detected from Protocol.load's own
% banner, so it reports on behavior rather than on instrumentation.
out = evalc('epsych.Runtime.phaseParameterData(string(filepath), UseCache=false, FastParse=true);');
tf = ~contains(out, '[INFO] Protocol loaded from:');
end


function S = snapshot(R)
S = arrayfun(@(p) p.toStruct(), R.all_parameters(includeInvisible=true), 'UniformOutput', false);
end


function restoreState(R, pLevel)
% Put the live parameters back to a fixed pre-load state so the two cycles
% start from the same place.
pLevel.Value = 40;
R.find_parameter('StimDelay').Value = 1;
R.find_parameter('RespWinDelay').Expression = 'StimDelay + 100';
end


function a = normAccess(a)
% hw.Parameter.fromStruct folds the legacy 'Read / Write' spelling to 'Any'.
if strcmpi(strtrim(char(string(a))), 'Read / Write'), a = 'Any'; end
end


function f = dirFiles(root, pattern)
f = strings(0,1);
if ~isfolder(root), return, end
d = dir(fullfile(root, pattern));
d(logical([d.isdir])) = [];
for k = 1:numel(d)
    f(end+1,1) = string(fullfile(d(k).folder, d(k).name)); %#ok<AGROW>
end
end


function rmprefIfSet(group, key)
% Remove a preference only if it exists; rmpref errors on a missing key.
if ispref(group, key)
    rmpref(group, key);
end
end
