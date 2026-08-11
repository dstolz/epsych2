function smoke_test_phase_protocol()
% smoke_test_phase_protocol()
% Exercise the unified phase/protocol workflow: saving a phase creates a
% protocol (.eprot) and loading a phase reads a protocol. Covers
% Runtime.writeParametersProtocol, Runtime.readParameters (protocol and legacy
% JSON sources), Runtime.phaseParameterData, and gui.PhaseSelector file
% discovery across both formats.
%
%   matlab -batch "run('tmp/smoke_test_phase_protocol.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_phase_protocol');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% ===== Setup: protocol + runtime sharing its interfaces ==================
P = epsych.Protocol(Name='PhaseTest', Info='Source protocol');
P.addParameter('Software', 'StimLevel', [10 20 30], Unit='dB', Type='Float');
P.addParameter('Software', 'RespWin', 1.5, Unit='s', Type='Float');

R = epsych.Runtime;
R.Interfaces = P.Interfaces; % same handles: live values reside in the protocol
R.Protocol = P;

pLevel = R.find_parameter('StimLevel');
pResp  = R.find_parameter('RespWin');
pLevel.Value = 20;
pResp.Value = 1.5;

phaseFile = fullfile(tmpDir, 'phaseA.eprot');

% ===== A. Saving a phase creates a protocol =============================
try
    R.writeParametersProtocol(phaseFile, "Phase A");
    assert(isfile(phaseFile), 'phase .eprot was not written');

    % The file is a real protocol: it loads standalone with the live values.
    P2 = epsych.Protocol.load(phaseFile);
    assert(strcmp(P2.Info, 'Phase A'), 'description should be stored as protocol Info');
    p2 = P2.Interfaces(1).find_parameter('StimLevel');
    assert(isequal(p2.Value, 20), 'saved protocol should carry the live Value');
    assert(isequal(cell2mat(p2.Values), [10 20 30]), 'saved protocol should carry design-time Values');

    % Saving a phase must not mutate the live protocol.
    assert(strcmp(P.Info, 'Source protocol'), 'live protocol Info must be untouched');

    fprintf('PASS: A. saving a phase creates a loadable protocol\n');
catch ME
    failures{end+1} = sprintf('A. save phase: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Loading a phase reads a protocol ==============================
try
    pLevel.Value = 30;
    pResp.Value = 0.5;

    loaded = R.readParameters(phaseFile);
    assert(numel(loaded) >= 2, 'both parameters should resolve');
    assert(isequal(pLevel.Value, 20), 'StimLevel should be restored from the phase protocol');
    assert(isequal(pResp.Value, 1.5), 'RespWin should be restored from the phase protocol');

    assert(R.Phase(end).Source == "Protocol", 'phase log should record a Protocol source');
    assert(R.Phase(end).Description == "Phase A", 'phase log should carry the protocol Info');
    assert(string(R.Phase(end).FilePath) == string(phaseFile), 'phase log should record the file path');

    fprintf('PASS: B. loading a phase applies the protocol''s parameters\n');
catch ME
    failures{end+1} = sprintf('B. load phase: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Legacy JSON phases still load =================================
try
    jsonFile = fullfile(tmpDir, 'phaseB.json');
    R.writeParametersJSON(jsonFile, "Phase B legacy");
    assert(isfile(jsonFile), 'legacy JSON phase was not written');

    pLevel.Value = 10;
    R.readParametersJSON(jsonFile); % back-compat wrapper -> readParameters
    assert(isequal(pLevel.Value, 20), 'StimLevel should be restored from the legacy JSON phase');
    assert(R.Phase(end).Source == "JSON", 'phase log should record a JSON source');
    assert(R.Phase(end).Description == "Phase B legacy", 'phase log should carry the JSON description');

    fprintf('PASS: C. legacy JSON phases load through the unified path\n');
catch ME
    failures{end+1} = sprintf('C. legacy JSON: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. phaseParameterData yields one shape for both formats ==========
try
    [pd1, md1] = epsych.Runtime.phaseParameterData(phaseFile);
    [pd2, md2] = epsych.Runtime.phaseParameterData(fullfile(tmpDir, 'phaseB.json'));
    assert(md1.Source == "Protocol" && md2.Source == "JSON", 'sources should be tagged');
    assert(all(isfield(pd1, {'Name','Value','Values','Expression','ParentType'})), ...
        'protocol entries missing expected fields');
    assert(all(isfield(pd2, {'Name','Value','Values','Expression','ParentType'})), ...
        'JSON entries missing expected fields');
    names1 = string({pd1.Name});
    assert(all(ismember(["StimLevel","RespWin"], names1)), 'protocol entries should list both parameters');
    fprintf('PASS: D. phaseParameterData normalizes both formats\n');
catch ME
    failures{end+1} = sprintf('D. phaseParameterData: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. PhaseSelector discovers both formats ==========================
try
    ps = gui.PhaseSelector(R, tmpDir);
    assert(all(ismember(["phaseA","phaseB"], ps.Names)), ...
        'PhaseSelector should list .eprot and .json phases');
    assert(numel(ps.FullFilenames) == 2, 'expected exactly two phase files');
    fprintf('PASS: E. PhaseSelector lists .eprot and legacy .json phases\n');
catch ME
    failures{end+1} = sprintf('E. PhaseSelector: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== F. Guards ========================================================
try
    % No protocol on the runtime -> explicit error.
    R2 = epsych.Runtime;
    threw = false;
    try
        R2.writeParametersProtocol(fullfile(tmpDir, 'nope.eprot'));
    catch guardME
        threw = strcmp(guardME.identifier, 'epsych:Runtime:NoProtocol');
    end
    assert(threw, 'writeParametersProtocol without a Protocol should raise epsych:Runtime:NoProtocol');

    % Missing extension defaults to .eprot.
    R.writeParametersProtocol(fullfile(tmpDir, 'noext'));
    assert(isfile(fullfile(tmpDir, 'noext.eprot')), 'extensionless path should be saved as .eprot');

    fprintf('PASS: F. guards (missing protocol, default extension)\n');
catch ME
    failures{end+1} = sprintf('F. guards: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end

% ===== G. Phase load schedules and applies a safe-boundary recompile ====
try
    P3 = epsych.Protocol(Name='RecompileTest', Info='Recompile source');
    P3.addParameter('Software', 'ToneLevel', [10 20 30], Unit='dB', Type='Float');
    P3.addParameter('Software', 'TrialType', [0 1], Type='Integer');
    sw = P3.findInterface('Software');
    sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
    sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
    sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);
    P3.compile();

    R3 = epsych.Runtime;
    R3.isTest = true;
    R3.HELPER = epsych.Helper;
    R3.Interfaces = P3.Interfaces;
    R3.Protocol = P3;
    R3.dfltDataPath = tmpDir;
    R3.TempDataDir = tmpDir;

    subject = epsych.DefaultSubject(struct('Name', 'SmokeSubject', ...
        'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));
    CONFIG = struct('PROTOCOL', P3, 'SUBJECT', subject);
    R3 = ep_TimerFcn_Start(R3, CONFIG);

    assert(isfield(R3.TRIALS, 'protocol') && R3.TRIALS(1).protocol == P3, ...
        'ep_TimerFcn_Start should record the protocol handle in TRIALS');

    % Save the phase with the original trial structure...
    phaseG = fullfile(tmpDir, 'phaseG.eprot');
    R3.writeParametersProtocol(phaseG, "Recompile phase");

    % ...then change the live design-time structure, as a later stage might.
    pTone = R3.find_parameter('ToneLevel');
    pTone.Values = {99};
    pTone.Value = 99;

    % Loading the phase restores the structure and schedules the recompile.
    R3.readParameters(phaseG);
    assert(R3.TRIALS(1).RECOMPILE_REQUESTED, 'phase load should set RECOMPILE_REQUESTED');
    assert(isequal(cell2mat(pTone.Values), [10 20 30]), 'phase load should restore design-time Values');

    % Drive one trial boundary; FORCE_TRIAL skips waiting on hardware.
    R3.TRIALS(1).FORCE_TRIAL = true;
    R3 = ep_TimerFcn_RunTime(R3);

    assert(~R3.TRIALS(1).RECOMPILE_REQUESTED, 'boundary should clear the recompile flag');
    col = R3.TRIALS(1).writeParamIdx.ToneLevel;
    lv = unique(cell2mat(R3.TRIALS(1).trials(:,col)));
    assert(isequal(lv(:).', [10 20 30]), 'recompiled trials should carry the phase''s Values');

    fprintf('PASS: G. phase load recompiles the protocol at the trial boundary\n');
catch ME
    failures{end+1} = sprintf('G. recompile on load: %s', ME.message);
    fprintf('FAIL: G. %s\n', ME.message);
end

% ===== H. Phase save captures runtime edits =============================
% Runtime edits arrive by two paths that toStruct alone does not capture:
% a deferred commit (gui.Parameter_Update) lands only in TRIALS.trials until
% the next dispatch, and no path refreshes design-time Values. The save must
% reconcile both, while leaving per-trial-managed columns (staircase) alone.
try
    P5 = epsych.Protocol(Name='SyncTest', Info='Runtime edit sync');
    P5.addParameter('Software', 'RespDur', 500, Type='Float');   % deferred commit target
    P5.addParameter('Software', 'PCatch', 0.1, Type='Float');    % live-only (autoCommit-style) edit
    P5.addParameter('Software', 'Stair', 1, Type='Float');       % per-trial managed column
    P5.addParameter('Software', 'Lvl', [10 20 30], Type='Float');% roved: untouched
    P5.addParameter('Software', 'TrialType', [0 1], Type='Integer');
    pCatch = P5.Interfaces(1).find_parameter('PCatch');
    pCatch.UpdateEveryTrial = false; % dispatch never touches it; live Value is authoritative
    sw = P5.findInterface('Software');
    sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
    sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
    sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);
    P5.compile();

    R5 = epsych.Runtime;
    R5.isTest = true;
    R5.HELPER = epsych.Helper;
    R5.Interfaces = P5.Interfaces;
    R5.Protocol = P5;
    R5.dfltDataPath = tmpDir;
    R5.TempDataDir = tmpDir;

    subject = epsych.DefaultSubject(struct('Name', 'SyncSubject', ...
        'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));
    R5 = ep_TimerFcn_Start(R5, struct('PROTOCOL', P5, 'SUBJECT', subject));

    % Deferred commit: table only, parameter untouched (mimics
    % gui.Parameter_Update.commit_changes without the immediate modifier).
    idx = R5.TRIALS(1).writeParamIdx.RespDur;
    T5 = R5.TRIALS(1).trials;
    [T5{:, idx}] = deal(750);
    % Per-trial managed column: rows diverge, as a staircase selector would leave them.
    idx = R5.TRIALS(1).writeParamIdx.Stair;
    T5{1, idx} = 0.4;
    R5.TRIALS(1).trials = T5;

    % Live-only edit (mimics an autoCommit control on a non-dispatched parameter).
    pCatch.Value = 0.25;

    phaseH = fullfile(tmpDir, 'phaseH.eprot');
    R5.writeParametersProtocol(phaseH, "Runtime edits");

    F = load(phaseH, '-mat');
    saved = struct;
    for ii = 1:numel(F.protocol.InterfaceData)
        for mm = 1:numel(F.protocol.InterfaceData{ii}.Modules)
            pp = F.protocol.InterfaceData{ii}.Modules{mm}.Parameters;
            for kk = 1:numel(pp)
                saved.(matlab.lang.makeValidName(pp{kk}.Name)) = pp{kk};
            end
        end
    end

    assert(isequal(saved.RespDur.Value, 750) && isequal(saved.RespDur.Values, {750}), ...
        'deferred table commit should be captured in both Value and Values');
    assert(isequal(saved.PCatch.Value, 0.25) && isequal(saved.PCatch.Values, {0.25}), ...
        'live-only edit should be captured in both Value and Values');
    assert(isequal(saved.Stair.Values, {1}), ...
        'per-trial managed parameter Values must not be overwritten by the save');
    assert(isequal(cell2mat(saved.Lvl.Values), [10 20 30]), ...
        'roved Values list must be preserved');

    % Round trip: loading the phase and recompiling regenerates the trial
    % table with the runtime-edited value rather than reverting it.
    pResp = R5.find_parameter('RespDur');
    pResp.Values = {500};
    pResp.Value = 500;
    R5.readParameters(phaseH);
    assert(isequal(pResp.Value, 750), 'phase load should restore the edited value');
    assert(isequal(pResp.Values, {750}), 'phase load should restore the edited design Values');
    R5.TRIALS(1).FORCE_TRIAL = true;
    R5 = ep_TimerFcn_RunTime(R5);
    col = R5.TRIALS(1).writeParamIdx.RespDur;
    lv = unique(cell2mat(R5.TRIALS(1).trials(:, col)));
    assert(isequal(lv, 750), 'recompiled trials should carry the edited value, not the stale design value');

    fprintf('PASS: H. phase save captures runtime edits and survives the recompile\n');
catch ME
    failures{end+1} = sprintf('H. runtime edit sync: %s', ME.message);
    fprintf('FAIL: H. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_phase_protocol: ALL PASS\n');
else
    fprintf('\nsmoke_test_phase_protocol: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_phase_protocol:failed', '%d failure(s)', numel(failures));
end

end
