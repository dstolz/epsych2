function smoke_test_hw_benchmark_runexpt()
% smoke_test_hw_benchmark_runexpt()
% The RunExpt side of Utilities > Hardware > I/O Benchmark...:
%   1) while the benchmark runs, Run, Preview and Pause (and the setup menu
%      items) are disabled and Stop is enabled
%   2) pressing Stop through the real button callback ends the benchmark
%      promptly with no results, says so on the status bar, and gives the
%      controls back
%   3) a benchmark left to finish leaves its results in the base workspace and
%      also gives the controls back
%   4) a Run/Preview click that arrives mid-benchmark does nothing
%
% The button press comes from a timer, which fires at the drawnow inside the
% benchmark's CancelFcn -- the same way an operator's click reaches it.
%
% Run headless: matlab -batch "run('tmp/smoke_test_hw_benchmark_runexpt.m')"
%
% See also: epsych.RunExpt.LaunchHardwareBenchmark, hw.benchmarkIO

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(fullfile(here, '..', 'examples', 'hw_benchmark'));

groups = {'ep_RunExpt_Subjects', 'ep_RunExpt_Setup'};
saved = cellfun(@(g) localSavePrefs(g), groups, 'uni', 0);
cleanupPrefs = onCleanup(@() localRestoreAll(groups, saved));

root = fullfile(tempdir, 'epsych_benchmark_runexpt');
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanupDir = onCleanup(@() localRemoveDir(root));
cleanupFigs = onCleanup(@() localCloseAll());
cleanupBase = onCleanup(@() evalin('base', 'clear benchmarkIO_results bench_probe'));

protoFile = create_hw_benchmark_protocol(fullfile(root, 'HwBenchmark_Software.eprot'));
rosterFile = fullfile(root, 'lab.esub');
epsych.SubjectRoster.setConfiguredFile(rosterFile);
R = epsych.SubjectRoster(rosterFile);
pid = R.addProject('Bench Study', DefaultProtocol = protoFile, ...
    DefaultDataPath = fullfile(root, 'data'), SavingFcn = 'ep_SaveDataFcn', ...
    BehaviorGUI = epsych.SubjectRoster.BEHAVIORGUI_NONE);
s1 = R.addSubject(struct('Name', 'BNCH1', 'Sex', 'Male', 'Species', 'Mouse'));
R.assign(s1, pid);
R.rememberProtocol(s1, pid, protoFile);

delete(findall(groot, 'Type', 'figure', 'Tag', 'RunExpt'));
rx = epsych.RunExpt("Bench Study", Subjects = "BNCH1", ReuseExisting = false);
% Big enough buffers that the benchmark outlasts the timer that presses Stop.
sizes = [131072 524288];

ctl = @() [rx.H.ctrl_run, rx.H.ctrl_preview, rx.H.ctrl_pauseall, rx.H.ctrl_halt];
isOn = @(h) arrayfun(@(x) strcmp(x.Enable, 'on'), h);

assert(isequal(isOn(ctl()), [true true false false]), ...
    'before the benchmark: Run and Preview on, Pause and Stop off');
fprintf('PASS: READY state has Run/Preview on, Pause/Stop off\n');

% 1 + 2. Lock-out, then Stop -----------------------------------------------
evalin('base', 'clear benchmarkIO_results bench_probe');
setappdata(0, 'bench_fired', false);
tm = timer(ExecutionMode = 'fixedSpacing', Period = 0.02, TimerFcn = @(~,~) localProbeThenPress(rx, isOn, ctl));
start(tm);
t0 = tic;
rx.LaunchHardwareBenchmark(Sizes = sizes, Repeats = 3000);
elapsed = toc(t0);
stop(tm); delete(tm);

assert(evalin('base', 'exist(''bench_probe'', ''var'')') == 1, ...
    'the mid-benchmark probe did not run: %s', string(getappdata(0, 'bench_cb_error')));
probe = evalin('base', 'bench_probe');
assert(isequal(probe.during, [false false false true]), ...
    'during the benchmark: Run, Preview and Pause off and Stop on (got %s)', mat2str(probe.during));
assert(probe.setupLocked, 'the setup menu items must be disabled during the benchmark');
fprintf('PASS: Run/Preview/Pause are disabled and Stop is enabled while it runs\n');

assert(~evalin('base', 'exist(''benchmarkIO_results'', ''var'')'), ...
    'a stopped benchmark must leave no results');
assert(contains(rx.H.statusBar.Label.Text, 'stopped', IgnoreCase = true), ...
    'the status bar must say the benchmark was stopped (got "%s")', rx.H.statusBar.Label.Text);
assert(isequal(isOn(ctl()), [true true false false]), ...
    'after Stop: Run and Preview back on, Pause and Stop off (got %s)', mat2str(isOn(ctl())));
fprintf('PASS: Stop ends the benchmark with no results and restores the controls (%.1f s)\n', elapsed);

% 4. A stale Run click mid-benchmark does nothing --------------------------
setappdata(0, 'bench_fired', false);
tm = timer(ExecutionMode = 'fixedSpacing', Period = 0.02, TimerFcn = @(~,~) localPressRunThenStop(rx));
start(tm);
rx.LaunchHardwareBenchmark(Sizes = sizes, Repeats = 3000);
stop(tm); delete(tm);
assert(rx.STATE == PRGMSTATE.READY, ...
    'a Run click during the benchmark must not start a session (STATE = %s)', string(rx.STATE));
fprintf('PASS: a Run click during the benchmark starts nothing\n');

% 3. Left to finish ----------------------------------------------------------
evalin('base', 'clear benchmarkIO_results');
rx.LaunchHardwareBenchmark(Sizes = [1024 4096]);
assert(evalin('base', 'exist(''benchmarkIO_results'', ''var'')') == 1, ...
    'a finished benchmark leaves benchmarkIO_results in the base workspace');
assert(isequal(isOn(ctl()), [true true false false]), 'a finished benchmark restores the controls');
assert(contains(rx.H.statusBar.Label.Text, 'finished', IgnoreCase = true), ...
    'the status bar must say the benchmark finished (got "%s")', rx.H.statusBar.Label.Text);
fprintf('PASS: a finished benchmark keeps its results and restores the controls\n');

fprintf('\nAll hw.benchmarkIO RunExpt checks passed.\n');
end

% -----------------------------------------------------------------------
function localProbeThenPress(rx, isOn, ctl)
% What the operator sees mid-benchmark, then the Stop click. Acts once, and only
% when the window is in the benchmark's lock-out state (Stop on), so it does
% not depend on how long the benchmark takes to start.
if getappdata(0, 'bench_fired') || ~strcmp(rx.H.ctrl_halt.Enable, 'on')
    return
end
setappdata(0, 'bench_fired', true);
try
    probe.during = isOn(ctl());
    % The benchmark's own menu item carries the 'setup' tag prefix, so it is
    % locked with the rest of them (findobj over the figure also returns a web
    % component that has no Tag, so ask for the item directly).
    probe.setupLocked = strcmp(rx.H.mnu_hw_benchmark.Enable, 'off');
    assignin('base', 'bench_probe', probe);
catch ME
    % A timer swallows its callback's error; hand it to the test to report.
    setappdata(0, 'bench_cb_error', getReport(ME, 'basic'));
end
rx.H.ctrl_halt.ButtonPushedFcn(rx.H.ctrl_halt, []);
end
% -----------------------------------------------------------------------
function localPressRunThenStop(rx)
% A click on a button that should be dead, then Stop so the test can go on.
if getappdata(0, 'bench_fired') || ~strcmp(rx.H.ctrl_halt.Enable, 'on')
    return
end
setappdata(0, 'bench_fired', true);
rx.H.ctrl_run.ButtonPushedFcn(rx.H.ctrl_run, []);
rx.H.ctrl_halt.ButtonPushedFcn(rx.H.ctrl_halt, []);
end

% -----------------------------------------------------------------------
function localCloseAll()
delete(findall(groot, 'Type', 'figure', '-regexp', 'Name', '^hw\.benchmarkIO'));
if isappdata(0, 'bench_fired'), rmappdata(0, 'bench_fired'); end
figs = findall(groot, 'Type', 'figure', 'Tag', 'RunExpt');
for f = figs(:)'
    try
        u = f.UserData;
        f.CloseRequestFcn = '';
        if isobject(u) && isvalid(u), delete(u); end
        if isgraphics(f), delete(f); end
    catch ME
        vprintf(2, ME);
    end
end
end

% -----------------------------------------------------------------------
function saved = localSavePrefs(group)
saved = struct('existed', ispref(group), 'values', struct());
if saved.existed
    saved.values = getpref(group);
end
end

% -----------------------------------------------------------------------
function localRestoreAll(groups, saved)
for i = 1:numel(groups)
    if ispref(groups{i}), rmpref(groups{i}); end
    if saved{i}.existed
        fn = fieldnames(saved{i}.values);
        for k = 1:numel(fn)
            setpref(groups{i}, fn{k}, saved{i}.values.(fn{k}));
        end
    end
end
end

% -----------------------------------------------------------------------
function localRemoveDir(root)
try
    if isfolder(root), rmdir(root, 's'); end
catch
    % A file handle the OS has not released yet; the temp folder is fine.
end
end
