function smoke_test_autocommit_trialsync()
% smoke_test_autocommit_trialsync()
% Regression test for autoCommit GUI edits being reverted by the trial table.
%
% An autoCommit gui.Parameter_Control historically wrote only the live
% hw.Parameter. For a parameter the dispatcher refreshes every trial
% (UpdateEveryTrial), the stale trial-table value then clobbered the edit at
% the next trial boundary, and Runtime.writeParametersProtocol recorded the
% stale table value into the phase file (the "Staircase parameters are not
% saved" bug, 2026-08-11). Wiring the control with Runtime= makes the commit
% land in TRIALS.trials as well; session-control toggles stay unwired because
% they rely on the table re-assert to self-clear.
%
%   matlab -batch "run('tmp/smoke_test_autocommit_trialsync.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_autocommit_trialsync');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% ===== Setup: protocol + running-session TRIALS ==========================
P = epsych.Protocol(Name='TrialSyncTest', Info='autoCommit trial sync');
P.addParameter('Software', 'StepOnHit', 0.03, Type='Float');   % dispatched (UpdateEveryTrial) staircase-style knob
P.addParameter('Software', 'StepOnMiss', 0.09, Type='Float');  % non-dispatched knob (data-fix configuration)
P.addParameter('Software', 'Reminder', false, Type='Boolean'); % self-clearing toggle: must NOT sync
P.addParameter('Software', 'TrialType', [0 1], Type='Integer');
sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);
pMiss = P.Interfaces(1).find_parameter('StepOnMiss');
pMiss.UpdateEveryTrial = false;
pRem = P.Interfaces(1).find_parameter('Reminder');
pRem.UpdateEveryTrial = false; % operator toggle: transient session control
P.compile();

R = epsych.Runtime;
R.isTest = true;
R.HELPER = epsych.Helper;
R.Interfaces = P.Interfaces;
R.Protocol = P;
R.dfltDataPath = tmpDir;
R.TempDataDir = tmpDir;

subject = epsych.DefaultSubject(struct('Name', 'SyncSubject', ...
    'Species', 'Mouse', 'Sex', 'Unknown', 'BoxID', 1));
R = ep_TimerFcn_Start(R, struct('PROTOCOL', P, 'SUBJECT', subject));

pHit = R.find_parameter('StepOnHit');

% add_parameter seeds Values, not Value; give every control a live value to
% display, as the runtime would have by the first trial.
pHit.Value  = 0.03;
pMiss.Value = 0.09;
pRem.Value  = false;

fig = uifigure(Visible='off');
cleanupFig = onCleanup(@() delete(fig));
gl = uigridlayout(fig, [8 1]);

% ===== A. Wired autoCommit edit lands on parameter AND trial table =======
try
    hHit = gui.Parameter_Control(gl, pHit, autoCommit=true, Runtime=R, Text='Step on Hit');
    simulate_edit(hHit, 0.05);

    assert(isequal(pHit.Value, 0.05), 'edit should commit to the parameter');
    col = R.TRIALS(1).writeParamIdx.StepOnHit;
    vals = unique(cell2mat(R.TRIALS(1).trials(:, col)));
    assert(isequal(vals, 0.05), 'edit should land in every trial-table row');

    fprintf('PASS: A. wired autoCommit edit syncs the trial table\n');
catch ME
    failures{end+1} = sprintf('A. table sync: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Edits survive a trial dispatch =================================
% The dispatched knob survives because the synced table re-asserts the edit;
% the non-dispatched knob survives because dispatch leaves it alone.
try
    hMiss = gui.Parameter_Control(gl, pMiss, autoCommit=true, Runtime=R, Text='Step on Miss');
    simulate_edit(hMiss, 0.12);

    R.TRIALS(1).FORCE_TRIAL = true;
    R = ep_TimerFcn_RunTime(R);

    assert(isequal(pHit.Value, 0.05), 'dispatched knob must keep the edit after a trial boundary');
    assert(isequal(pMiss.Value, 0.12), 'non-dispatched knob must keep the edit after a trial boundary');

    fprintf('PASS: B. edits survive a trial dispatch\n');
catch ME
    failures{end+1} = sprintf('B. dispatch: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Phase save records the edited values ===========================
try
    phaseFile = fullfile(tmpDir, 'sync.eprot');
    R.writeParametersProtocol(phaseFile, 'autoCommit sync');

    F = load(phaseFile, '-mat');
    saved = struct;
    for ii = 1:numel(F.protocol.InterfaceData)
        for mm = 1:numel(F.protocol.InterfaceData{ii}.Modules)
            pp = F.protocol.InterfaceData{ii}.Modules{mm}.Parameters;
            for kk = 1:numel(pp)
                saved.(matlab.lang.makeValidName(pp{kk}.Name)) = pp{kk};
            end
        end
    end

    assert(isequal(saved.StepOnHit.Value, 0.05) && isequal(saved.StepOnHit.Values, {0.05}), ...
        'phase save should record the edited dispatched knob');
    assert(isequal(saved.StepOnMiss.Value, 0.12) && isequal(saved.StepOnMiss.Values, {0.12}), ...
        'phase save should record the edited non-dispatched knob');

    fprintf('PASS: C. phase save records autoCommit edits\n');
catch ME
    failures{end+1} = sprintf('C. phase save: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Unwired toggle stays out of the trial table ====================
try
    colR = R.TRIALS(1).writeParamIdx.Reminder;
    before = R.TRIALS(1).trials(:, colR);

    hRem = gui.Parameter_Control(gl, pRem, Type='toggle', autoCommit=true, Text='Reminder');
    simulate_edit(hRem, true);

    assert(isequal(logical(pRem.Value), true), 'toggle should commit to the parameter');
    assert(isequal(R.TRIALS(1).trials(:, colR), before), ...
        'unwired toggle must not touch the trial table (self-clear semantics)');

    fprintf('PASS: D. unwired toggle leaves the trial table alone\n');
catch ME
    failures{end+1} = sprintf('D. toggle: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. Guards: pre-run runtime and bound-property edits ===============
try
    % Pre-run: TRIALS never populated -> the sync is a silent no-op.
    P2 = epsych.Protocol(Name='PreRun');
    P2.addParameter('Software', 'Knob', 5, Type='Float');
    R2 = epsych.Runtime;
    R2.Interfaces = P2.Interfaces;
    R2.Protocol = P2;
    pKnob = R2.find_parameter('Knob');
    pKnob.Value = 5;
    hKnob = gui.Parameter_Control(gl, pKnob, autoCommit=true, Runtime=R2, Text='Knob');
    simulate_edit(hKnob, 7);
    assert(isequal(pKnob.Value, 7), 'pre-run edit should still commit to the parameter');

    % Bound-property edit: host-side state, no trial-table column to sync.
    colH = R.TRIALS(1).writeParamIdx.StepOnHit;
    beforeH = R.TRIALS(1).trials(:, colH);
    hMin = gui.Parameter_Control(gl, pHit, autoCommit=true, Runtime=R, BoundProperty='Min', Text='Min');
    simulate_edit(hMin, 0.001);
    assert(isequal(pHit.Min, 0.001), 'bound-property edit should commit');
    assert(isequal(R.TRIALS(1).trials(:, colH), beforeH), ...
        'bound-property edit must not rewrite the trial table');

    fprintf('PASS: E. pre-run and bound-property guards\n');
catch ME
    failures{end+1} = sprintf('E. guards: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== Summary ==========================================================
if isempty(failures)
    fprintf('\nsmoke_test_autocommit_trialsync: ALL PASS\n');
else
    fprintf('\nsmoke_test_autocommit_trialsync: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_autocommit_trialsync:failed', '%d failure(s)', numel(failures));
end

end


function simulate_edit(h, newValue)
% simulate_edit(h, newValue)
% Drive a gui.Parameter_Control the way a user edit does: put the value on
% the widget, then fire the ValueChanged path with a non-empty source so the
% autoCommit branch runs.
if isprop(h.h_uiobj, 'Value')
    h.h_uiobj.Value = newValue;
end
e = struct('PreviousValue', [], 'EventName', 'ValueChanged');
e.Value = newValue;
h.value_changed(h.h_uiobj, e);
end
