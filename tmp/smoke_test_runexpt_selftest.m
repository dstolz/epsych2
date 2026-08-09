function report = smoke_test_runexpt_selftest()
% report = smoke_test_runexpt_selftest()
% Smoke test for the RunExpt self-test feature (epsych.SelfTest, gui.SelfTest,
% and the hw.Interface.selfTest hook).
%
% No hardware is required: every opt-in group stays disabled, so nothing
% connects, no box GUI is launched, and the session window's state is never
% driven. Only temporary files are written.
%
% Verifies:
%   1) The group catalog is well formed and every method it names exists.
%   2) The engine runs headlessly with no session, skipping session-dependent
%      groups rather than erroring, and restores GVerbosity afterwards.
%   3) hw.Interface.selfTest returns the empty prototype by default and
%      hw.Software's override returns a well-formed result.
%   4) The engine detects a deliberately broken saving function.
%   5) The window opens, runs, populates its table, enforces a single
%      instance, and closes without leaving figures or timers behind.
%   6) formatReport and saveReport produce output.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

global GVerbosity
priorVerbosity = GVerbosity;
cleanupVerbosity = onCleanup(@() localRestoreVerbosity(priorVerbosity));

% Step 1: catalog integrity
stepName = 'catalog';
try
    C = epsych.SelfTest.catalog();
    assert(~isempty(C), 'SmokeTest:EmptyCatalog', 'The catalog is empty.');

    fields = {'id','label','method','mutating'};
    for f = fields
        assert(isfield(C, f{1}), 'SmokeTest:CatalogField', ...
            'Catalog entries lack the "%s" field.', f{1});
    end

    ids = [C.id];
    assert(numel(unique(ids)) == numel(ids), 'SmokeTest:DuplicateGroupId', ...
        'Catalog contains duplicate group ids.');

    methodList = methods('epsych.SelfTest');
    for i = 1:numel(C)
        assert(ismember(char(C(i).method), methodList) || ...
            isfile(fullfile(fileparts(which('epsych.SelfTest')), [char(C(i).method) '.m'])), ...
            'SmokeTest:MissingMethod', ...
            'Catalog names method "%s", which does not exist.', C(i).method);
    end

    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('%d groups, all methods present.', numel(C)));
catch ME
    report.steps.(stepName) = struct('passed', false, ...
        'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: headless run with no session
stepName = 'headlessRun';
try
    GVerbosity = 1;
    st = epsych.SelfTest([]);
    st.Verbosity = 0;   % keep the smoke test quiet

    res = st.run();
    assert(~isempty(res), 'SmokeTest:NoResults', 'The engine produced no results.');

    resultFields = {'id','group','name','status','summary','detail','remedy','seconds','mutating'};
    for f = resultFields
        assert(isfield(res, f{1}), 'SmokeTest:ResultField', ...
            'Results lack the "%s" field.', f{1});
    end

    statuses = string({res.status});
    assert(all(ismember(statuses, epsych.SelfTest.STATUSES)), ...
        'SmokeTest:BadStatus', 'A result carries an unrecognized status.');

    % Session-dependent groups must skip, not fail, when nothing is loaded.
    sessionGroups = ["Config","Protocol","TrialSelection","Hardware","DataSaving","Gui"];
    for g = sessionGroups
        inGroup = res(strcmp(string({res.group}), g));
        assert(~isempty(inGroup), 'SmokeTest:MissingGroup', ...
            'Group "%s" produced no result.', g);
        assert(all(string({inGroup.status}) == "skip"), 'SmokeTest:UnexpectedFailure', ...
            'Group "%s" did not skip with no session loaded.', g);
    end

    assert(isequal(GVerbosity, 1), 'SmokeTest:VerbosityNotRestored', ...
        'GVerbosity was left at %g instead of being restored to 1.', GVerbosity);

    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('%d results; session groups skipped; verbosity restored.', numel(res)));
catch ME
    report.steps.(stepName) = struct('passed', false, ...
        'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: the hw.Interface.selfTest hook
stepName = 'interfaceSelfTestHook';
try
    proto = hw.Interface.selfTestResult();
    assert(isempty(proto), 'SmokeTest:PrototypeNotEmpty', ...
        'selfTestResult() with no arguments should return an empty struct array.');
    for f = {'name','status','summary','detail','remedy'}
        assert(isfield(proto, f{1}), 'SmokeTest:HookField', ...
            'The result prototype lacks the "%s" field.', f{1});
    end

    one = hw.Interface.selfTestResult('probe', 'pass', 'ok', ...
        Detail = ["a" "b"], Remedy = "none");
    assert(isscalar(one) && one.status == "pass" && numel(one.detail) == 2, ...
        'SmokeTest:HookBuilder', 'selfTestResult did not build the expected struct.');

    % hw.Software overrides the hook, so it must return something.
    sw = hw.Software;
    swResults = sw.selfTest();
    assert(~isempty(swResults), 'SmokeTest:SoftwareNoResults', ...
        'hw.Software.selfTest returned nothing; the override is missing.');
    assert(all(ismember(string({swResults.status}), ["pass","fail","warn","info","skip"])), ...
        'SmokeTest:SoftwareBadStatus', 'hw.Software.selfTest returned an unrecognized status.');

    % The invasive form must also be safe and non-throwing.
    swInvasive = sw.selfTest(Invasive = true);
    assert(~isempty(swInvasive), 'SmokeTest:SoftwareInvasive', ...
        'hw.Software.selfTest(Invasive=true) returned nothing.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Prototype, builder, and hw.Software override all behave correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, ...
        'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: a deliberately broken callback must be reported as a failure
stepName = 'detectsBrokenCallback';
rx = [];
try
    rx = epsych.RunExpt('', ReuseExisting=false, CleanupStaleFigures=false);
    cleanupRunExpt = onCleanup(@() localDeleteRunExpt(rx));

    rx.FUNCS.SavingFcn = 'this_function_does_not_exist_selftest';

    st = epsych.SelfTest(rx);
    st.Verbosity = 0;
    res = st.run("Functions");

    saving = res(strcmp(string({res.id}), "B1_SavingFcn"));
    assert(~isempty(saving), 'SmokeTest:MissingCheck', ...
        'The saving-function check did not run.');
    assert(saving.status == "fail", 'SmokeTest:NotDetected', ...
        'A nonexistent saving function was reported as "%s" rather than a failure.', saving.status);
    assert(strlength(saving.remedy) > 0, 'SmokeTest:NoRemedy', ...
        'The failure carries no remedy for the user to act on.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('Reported: %s', saving.summary));
catch ME
    report.steps.(stepName) = struct('passed', false, ...
        'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 5: the window
stepName = 'guiLifecycle';
try
    assert(~isempty(rx) && isvalid(rx), 'SmokeTest:PrereqFailed', ...
        'The RunExpt instance from the previous step is unavailable.');

    timersBefore = numel(timerfindall);

    rx.OpenSelfTest;
    drawnow;

    fig = findall(groot, 'Type', 'figure', 'Tag', 'RunExptSelfTest');
    assert(~isempty(fig), 'SmokeTest:WindowMissing', 'The self-test window did not open.');
    g = fig(1).UserData;
    assert(isa(g, 'gui.SelfTest'), 'SmokeTest:BadUserData', ...
        'The window UserData is a %s, not a gui.SelfTest.', class(g));

    C = epsych.SelfTest.catalog();
    assert(numel(g.H.groupNodes) == numel(C), 'SmokeTest:TreeMismatch', ...
        'The tree shows %d groups but the catalog has %d.', numel(g.H.groupNodes), numel(C));

    % Opt-ins must default off so the window never touches hardware unasked.
    assert(~g.H.optConnect.Value && ~g.H.optBoxFig.Value && ~g.H.optStateCycle.Value, ...
        'SmokeTest:OptInDefault', 'A side-effecting option defaulted to enabled.');

    g.H.verbosity.Value = 0;
    g.H.verbosity.ValueChangedFcn(g.H.verbosity, []);
    assert(g.Engine.Verbosity == 0, 'SmokeTest:VerbosityNotApplied', ...
        'Changing the verbosity dropdown did not reach the engine.');

    g.H.btnRunAll.ButtonPushedFcn(g.H.btnRunAll, []);
    drawnow;

    assert(size(g.H.table.Data, 1) > 0, 'SmokeTest:EmptyTable', ...
        'The results table is empty after running.');
    assert(size(g.H.table.Data, 2) == 5, 'SmokeTest:TableShape', ...
        'The results table has %d columns, expected 5.', size(g.H.table.Data, 2));
    assert(contains(g.H.status.Text, 'passed'), 'SmokeTest:NoTally', ...
        'The footer does not show a tally.');

    % Single instance
    gui.SelfTest(rx);
    drawnow;
    figs = findall(groot, 'Type', 'figure', 'Tag', 'RunExptSelfTest');
    assert(numel(figs) == 1, 'SmokeTest:NotSingleton', ...
        '%d self-test windows are open; only one should be.', numel(figs));

    g2 = figs(1).UserData;
    delete(g2);
    drawnow;
    assert(isempty(findall(groot, 'Type', 'figure', 'Tag', 'RunExptSelfTest')), ...
        'SmokeTest:WindowNotClosed', 'The self-test window did not close.');

    timersAfter = numel(timerfindall);
    assert(timersAfter == timersBefore, 'SmokeTest:TimerLeak', ...
        'The self-test left %d timer(s) behind.', timersAfter - timersBefore);

    report.steps.(stepName) = struct('passed', true, ...
        'detail', 'Window opened, ran, stayed singleton, and closed with no leaks.');
catch ME
    report.steps.(stepName) = struct('passed', false, ...
        'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 6: reporting
stepName = 'reporting';
try
    st = epsych.SelfTest([]);
    st.Verbosity = 0;
    res = st.run("Environment");

    txt = st.formatReport(res);
    assert(ischar(txt) && contains(txt, 'Self-Test Report'), 'SmokeTest:BadReport', ...
        'formatReport did not produce a report.');
    assert(contains(txt, 'Summary'), 'SmokeTest:NoSummary', ...
        'The report has no summary line.');

    ffn = fullfile(tempdir, sprintf('epsych_selftest_smoke_%s.txt', ...
        char(datetime('now', Format='yyMMddHHmmss'))));
    cleanupReport = onCleanup(@() localDeleteFile(ffn));

    st.saveReport(res, ffn);
    assert(isfile(ffn), 'SmokeTest:ReportNotWritten', 'saveReport wrote no file.');
    written = fileread(ffn);
    assert(contains(written, 'Self-Test Report'), 'SmokeTest:ReportContent', ...
        'The written report does not contain the expected header.');

    report.steps.(stepName) = struct('passed', true, ...
        'detail', sprintf('Report is %d characters; file written and read back.', numel(txt)));
catch ME
    report.steps.(stepName) = struct('passed', false, ...
        'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

stepNames = fieldnames(report.steps);
stepPassed = false(size(stepNames));
for i = 1:numel(stepNames)
    stepPassed(i) = logical(report.steps.(stepNames{i}).passed);
end
report.allPassed = all(stepPassed);

if report.allPassed
    fprintf('RunExpt self-test smoke test PASSED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
else
    fprintf('RunExpt self-test smoke test FAILED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
    for i = 1:numel(stepNames)
        if ~report.steps.(stepNames{i}).passed
            fprintf('  - %s failed:\n%s\n', stepNames{i}, report.steps.(stepNames{i}).detail);
        end
    end
end

end

% -----------------------------------------------------------------------
function localRestoreVerbosity(level)
global GVerbosity
GVerbosity = level;
end

% -----------------------------------------------------------------------
function localDeleteRunExpt(rx)
if ~isempty(rx) && isvalid(rx)
    delete(rx);
end
end

% -----------------------------------------------------------------------
function localDeleteFile(ffn)
if isfile(ffn)
    delete(ffn);
end
end
