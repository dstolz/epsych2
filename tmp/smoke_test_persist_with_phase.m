function smoke_test_persist_with_phase()
% smoke_test_persist_with_phase()
% Headless smoke test for the hw.Parameter PersistWithPhase flag (2026-08).
%
% hw.Parameter.isTransientControl treats every writable Boolean the trial
% dispatcher never refreshes as an operator button, so a phase neither saves
% nor restores its state. That is right for Deliver Trials / Reminder / Shape,
% and wrong for a setting the operator sets once and leaves set -- the
% "Present Catch Trials" checkbox (CatchTrialsEnabled), which
% cl_AppetitiveStimDetect creates outside the trial table. PersistWithPhase is
% how such a parameter opts out of the inference.
%
% Covers:
%   A. Flag plumbing: default false, constructor option, direct property set.
%   B. Serialization: toStruct carries it; fromStruct restores it; a legacy
%      struct without the field leaves the live flag alone (it is code-set,
%      not authored in the file).
%   C. isTransientControl: a PersistWithPhase Boolean is not transient; a
%      plain toggle still is; a trigger stays transient regardless.
%   D. Full phase round trip through Runtime.writeParametersProtocol /
%      readParameters: the flagged toggle is restored from the phase, the
%      plain toggle keeps its live value.
%   E. The selector's own parameter: cl_AppetitiveStimDetect's
%      CatchTrialsEnabled carries the flag.
%
%   matlab -batch "run('tmp/smoke_test_persist_with_phase.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_persistphase');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% ===== A. Flag plumbing =================================================
try
    P = epsych.Protocol(Name='PersistPhaseTest', Info='PersistWithPhase');
    sw = P.findInterface('Software');
    module = sw.Module;

    pPlain = module.add_parameter('DeliverTrials', false, Type='Boolean', ...
        UpdateEveryTrial=false);
    assert(~pPlain.PersistWithPhase, 'PersistWithPhase must default to false');

    pCatch = module.add_parameter('CatchTrialsEnabled', true, Type='Boolean', ...
        UpdateEveryTrial=false, PersistWithPhase=true);
    assert(pCatch.PersistWithPhase, 'constructor option must set PersistWithPhase');

    pLate = module.add_parameter('ObserveMode', false, Type='Boolean', ...
        UpdateEveryTrial=false);
    pLate.PersistWithPhase = true;
    assert(pLate.PersistWithPhase, 'PersistWithPhase must be settable after creation');

    % The flag is orthogonal to the dispatch flags: setting it must not
    % quietly enlist the parameter in the per-trial dispatch.
    assert(~pCatch.UpdateEveryTrial && ~pCatch.SetOnce, ...
        'PersistWithPhase must not change UpdateEveryTrial/SetOnce');

    fprintf('PASS: A. flag plumbing\n');
catch ME
    failures{end+1} = sprintf('A. plumbing: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Serialization round trip ======================================
try
    S = pCatch.toStruct();
    assert(isfield(S, 'PersistWithPhase') && logical(S.PersistWithPhase), ...
        'toStruct must carry PersistWithPhase');

    % The flag belongs to the code that owns the parameter, not to the file,
    % so fromStruct must not restore it in either direction. Restoring it
    % would let one phase saved from a session that predated the owner's
    % declaration demote a persistent setting back to a momentary button --
    % permanently, since every later save would then record the demotion too.
    Q = epsych.Protocol(Name='RoundTrip');
    qp = Q.findInterface('Software').Module.add_parameter('CatchTrialsEnabled', ...
        false, Type='Boolean');
    qp.fromStruct(S);
    assert(~qp.PersistWithPhase, ...
        'fromStruct must not set PersistWithPhase from the file');

    qp.PersistWithPhase = true;
    stale = S;
    stale.PersistWithPhase = false;   % saved before the owner declared the flag
    qp.fromStruct(stale);
    assert(qp.PersistWithPhase, ...
        'a stale file must not clear a live PersistWithPhase');

    legacy = rmfield(S, 'PersistWithPhase');
    qp.fromStruct(legacy);
    assert(qp.PersistWithPhase, ...
        'a legacy file without the field must not clear a live PersistWithPhase');

    fprintf('PASS: B. serialization round trip\n');
catch ME
    failures{end+1} = sprintf('B. serialization: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. isTransientControl ============================================
try
    assert(hw.Parameter.isTransientControl(pPlain), ...
        'an unflagged writable Boolean the dispatcher ignores is still a toggle');
    assert(~hw.Parameter.isTransientControl(pCatch), ...
        'a PersistWithPhase Boolean must not be treated as transient');

    % Struct form: this is what the load and save paths actually evaluate.
    assert(hw.Parameter.isTransientControl(pPlain.toStruct()), ...
        'struct form: plain toggle stays transient');
    assert(~hw.Parameter.isTransientControl(pCatch.toStruct()), ...
        'struct form: flagged toggle is not transient');
    assert(hw.Parameter.isTransientControl(rmfield(pPlain.toStruct(), 'PersistWithPhase')), ...
        'legacy struct without the field stays transient');

    % A trigger's value is the residue of its last firing; the flag cannot
    % make that worth saving.
    pTrig = module.add_parameter('ShapeTrial', 0, isTrigger=true);
    pTrig.PersistWithPhase = true;
    assert(hw.Parameter.isTransientControl(pTrig), ...
        'a trigger must stay transient even when flagged');
    pTrig.PersistWithPhase = false;

    fprintf('PASS: C. isTransientControl\n');
catch ME
    failures{end+1} = sprintf('C. isTransientControl: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Phase save/load round trip ====================================
try
    sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
    sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
    sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);
    P.compile();

    R = epsych.Runtime;
    R.isTest = true;
    R.EVENTS = epsych.EventHub;
    R.Interfaces = P.Interfaces;
    R.Protocol = P;
    R.DefaultDataPath = tmpDir;
    R.TempDataDir = tmpDir;

    subject = epsych.DefaultSubject(struct('Name', 'PersistSubject', ...
        'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));
    R = ep_TimerFcn_Start(R, struct('PROTOCOL', P, 'SUBJECT', subject));

    % Operator state at save time: catch trials OFF, trial delivery ON.
    pCatch.Value = false;
    pPlain.Value = true;

    phaseFile = fullfile(tmpDir, 'stage1.eprot');
    R.writeParametersProtocol(phaseFile);
    assert(isfile(phaseFile), 'phase file was not written');

    % The saved file must carry the flagged toggle's value in BOTH Value and
    % the design-time Values list -- a phase load schedules a recompile, and a
    % stale Values list would revert the setting at the next trial boundary.
    fileData = epsych.Runtime.phaseParameterData(phaseFile);
    names = string({fileData.Name});
    sCatch = fileData(names == "CatchTrialsEnabled");
    assert(isscalar(sCatch), 'CatchTrialsEnabled missing from the saved phase');
    assert(isequal(logical(sCatch.Value), false), ...
        'saved phase must record the flagged toggle as OFF');
    assert(~isempty(sCatch.Values) && isequal(logical(sCatch.Values{1}), false), ...
        'phase save must sync the flagged toggle into its design-time Values');

    % Now move both toggles to the opposite of what the phase holds, so a
    % restore and a no-op are distinguishable.
    pCatch.Value = true;
    pPlain.Value = false;

    R.readParameters(phaseFile);

    assert(isequal(logical(pCatch.Value), false), ...
        'phase load must restore the PersistWithPhase toggle');
    assert(isequal(logical(pPlain.Value), false), ...
        'phase load must leave the plain operator toggle at its live value');

    % Recovery case: a phase saved BEFORE the parameter's owner declared the
    % flag records PersistWithPhase = false. The live parameter is the
    % authority, so once the owner is updated that older file must load its
    % recorded value anyway -- otherwise every phase saved before the fix
    % would stay unloadable, and the first load of one would demote the live
    % parameter and re-break every subsequent save.
    stalePhase = fullfile(tmpDir, 'stage0.eprot');
    raw = builtin('load', phaseFile, '-mat');
    for i = 1:numel(raw.protocol.InterfaceData)
        mods = raw.protocol.InterfaceData{i}.Modules;
        for m = 1:numel(mods)
            prm = mods{m}.Parameters;
            for k = 1:numel(prm)
                if strcmp(prm{k}.Name, 'CatchTrialsEnabled')
                    prm{k}.PersistWithPhase = false;
                end
            end
            mods{m}.Parameters = prm;
        end
        raw.protocol.InterfaceData{i}.Modules = mods;
    end
    protocol = raw.protocol;
    builtin('save', char(stalePhase), 'protocol', '-mat');

    pCatch.Value = true;
    R.readParameters(stalePhase);
    assert(isequal(logical(pCatch.Value), false), ...
        'the live PersistWithPhase must override a stale file and restore the value');
    assert(pCatch.PersistWithPhase, ...
        'loading a stale phase must not clear the live PersistWithPhase');

    fprintf('PASS: D. phase save/load round trip (incl. stale-file recovery)\n');
catch ME
    failures{end+1} = sprintf('D. phase round trip: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. The selector marks its own toggle =============================
try
    src = fileread(fullfile(here, '..', 'paradigms', 'TrialSelectors', ...
        '@cl_AppetitiveStimDetect', 'cl_AppetitiveStimDetect.m'));
    tok = regexp(src, "ensureSelectorParameter_\('CatchTrialsEnabled'.*?\);", ...
        'match', 'once');
    assert(~isempty(tok), 'CatchTrialsEnabled creation call not found');
    assert(contains(tok, 'PersistWithPhase=true'), ...
        'cl_AppetitiveStimDetect must create CatchTrialsEnabled with PersistWithPhase=true');

    fprintf('PASS: E. selector marks CatchTrialsEnabled\n');
catch ME
    failures{end+1} = sprintf('E. selector: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_persist_with_phase: ALL PASS\n');
else
    fprintf('\nsmoke_test_persist_with_phase: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_persist_with_phase:failed', '%d failure(s)', numel(failures));
end

end
