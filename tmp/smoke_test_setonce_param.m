function smoke_test_setonce_param()
% smoke_test_setonce_param()
% Headless smoke test for the hw.Parameter SetOnce flag (2026-08): a writable
% parameter flagged SetOnce joins the session's FIRST trial dispatch only, so
% its value reaches the hardware once at session start and is never rewritten.
% 'Coefficient Buffer' parameters default to it, because rewriting a large,
% session-static buffer (e.g. calibration filter coefficients) every trial is
% pure waste.
%
% Covers:
%   A. Creation defaults: Coefficient Buffer -> SetOnce=true/UpdateEveryTrial=false,
%      explicit options win, other types unaffected, trigger default intact.
%   B. Serialization: toStruct/fromStruct round trip; legacy structs without
%      the field load as SetOnce=false.
%   C. isTransientControl: a Boolean the dispatcher writes once is a setting,
%      not an operator toggle.
%   D. Runtime dispatch: written on the first dispatch, skipped afterward,
%      while UpdateEveryTrial parameters keep being rewritten.
%
%   matlab -batch "run('tmp/smoke_test_setonce_param.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_setonce');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

nTaps = 65;
coefs = sin(linspace(0, pi, nTaps));

% ===== A. Creation defaults =============================================
try
    P = epsych.Protocol(Name='SetOnceTest', Info='SetOnce dispatch');
    sw = P.findInterface('Software');
    module = sw.Module;

    pFIR = module.add_parameter('FIRCoefs', {coefs}, ...
        Type='Coefficient Buffer', isArray=true);
    assert(pFIR.SetOnce, 'Coefficient Buffer should default SetOnce=true');
    assert(~pFIR.UpdateEveryTrial, 'Coefficient Buffer should default UpdateEveryTrial=false');

    pOverride = module.add_parameter('FIRCoefsEveryTrial', {coefs}, ...
        Type='Coefficient Buffer', isArray=true, SetOnce=false, UpdateEveryTrial=true);
    assert(~pOverride.SetOnce && pOverride.UpdateEveryTrial, ...
        'explicit SetOnce/UpdateEveryTrial options must win over the type default');

    pLevel = module.add_parameter('Level', [10 20], Type='Float');
    assert(~pLevel.SetOnce && pLevel.UpdateEveryTrial, ...
        'non-buffer types keep SetOnce=false, UpdateEveryTrial=true');

    pOnceFloat = module.add_parameter('SetupGain', 3, Type='Float', SetOnce=true);
    assert(pOnceFloat.SetOnce && ~pOnceFloat.UpdateEveryTrial, ...
        'SetOnce=true should default UpdateEveryTrial to false');

    pTrig = module.add_parameter('x_NewTrial_1', 0, isTrigger=true);
    assert(~pTrig.SetOnce && ~pTrig.UpdateEveryTrial, ...
        'trigger default (UpdateEveryTrial=false, SetOnce=false) must be intact');

    fprintf('PASS: A. creation defaults\n');
catch ME
    failures{end+1} = sprintf('A. defaults: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Serialization round trip ======================================
try
    S = pFIR.toStruct();
    assert(isfield(S, 'SetOnce') && logical(S.SetOnce), ...
        'toStruct must carry SetOnce');

    Q = epsych.Protocol(Name='RoundTrip');
    qp = Q.findInterface('Software').Module.add_parameter('FIRCoefs', 0);
    assert(~qp.SetOnce, 'plain Float starts SetOnce=false');
    qp.fromStruct(S);
    assert(qp.SetOnce && ~qp.UpdateEveryTrial, ...
        'fromStruct must restore SetOnce and UpdateEveryTrial');

    % Legacy struct: files saved before the flag existed have no SetOnce
    % field and must keep their original (never-dispatched) behavior even
    % for Coefficient Buffer types.
    legacy = rmfield(S, 'SetOnce');
    qp.fromStruct(legacy);
    assert(~qp.SetOnce, 'legacy struct without SetOnce must load as false');

    fprintf('PASS: B. serialization round trip\n');
catch ME
    failures{end+1} = sprintf('B. serialization: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. isTransientControl ============================================
try
    P2 = epsych.Protocol(Name='TransientTest');
    m2 = P2.findInterface('Software').Module;
    pToggle = m2.add_parameter('DeliverTrials', false, Type='Boolean');
    pToggle.UpdateEveryTrial = false;
    assert(hw.Parameter.isTransientControl(pToggle), ...
        'writable Boolean with both flags off is an operator toggle');

    pOnceBool = m2.add_parameter('EnableEqualizer', true, Type='Boolean', SetOnce=true);
    assert(~hw.Parameter.isTransientControl(pOnceBool), ...
        'a SetOnce Boolean is a session-start setting, not a transient toggle');

    % Struct form, with and without the field (legacy phase files)
    st = pToggle.toStruct();
    assert(hw.Parameter.isTransientControl(st), 'struct form: toggle stays transient');
    assert(hw.Parameter.isTransientControl(rmfield(st, 'SetOnce')), ...
        'legacy struct without SetOnce stays transient');
    assert(~hw.Parameter.isTransientControl(pOnceBool.toStruct()), ...
        'struct form: SetOnce Boolean is not transient');

    fprintf('PASS: C. isTransientControl\n');
catch ME
    failures{end+1} = sprintf('C. isTransientControl: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Runtime dispatch: once at start, then hands off ================
try
    sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
    sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);
    P.compile();

    R = epsych.Runtime;
    R.isTest = true;
    R.HELPER = epsych.Helper;
    R.Interfaces = P.Interfaces;
    R.Protocol = P;
    R.dfltDataPath = tmpDir;
    R.TempDataDir = tmpDir;

    subject = epsych.DefaultSubject(struct('Name', 'SetOnceSubject', ...
        'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));

    % ep_TimerFcn_Start populates TRIALS, which triggers the first dispatch
    % (TrialIndex == 1): the SetOnce buffer must be written here.
    R = ep_TimerFcn_Start(R, struct('PROTOCOL', P, 'SUBJECT', subject));

    assert(isequal(pFIR.Value(:), coefs(:)), ...
        'SetOnce buffer must be written by the first trial dispatch');
    assert(pFIR.lastUpdated > 0, 'first dispatch must stamp lastUpdated');

    % Overwrite with a sentinel (as a mid-session calibration load would),
    % then force a trial boundary: the per-trial dispatch must NOT rewrite
    % the SetOnce buffer, while the UpdateEveryTrial knob is refreshed from
    % the trial table as always.
    sentinel = -ones(1, nTaps);
    pFIR.Value = sentinel;
    pLevel.Value = 999;

    R.TRIALS(1).FORCE_TRIAL = true;
    R = ep_TimerFcn_RunTime(R);

    assert(isequal(pFIR.Value(:), sentinel(:)), ...
        'per-trial dispatch must leave the SetOnce buffer alone after trial 1');
    assert(ismember(pLevel.Value, [10 20]), ...
        'UpdateEveryTrial parameter must be rewritten from the trial table');
    assert(isequal(pOverride.Value(:), coefs(:)), ...
        'a buffer explicitly opted back into UpdateEveryTrial keeps dispatching');

    fprintf('PASS: D. dispatched once at session start, then left alone\n');
catch ME
    failures{end+1} = sprintf('D. dispatch: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_setonce_param: ALL PASS\n');
else
    fprintf('\nsmoke_test_setonce_param: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_setonce_param:failed', '%d failure(s)', numel(failures));
end

end
