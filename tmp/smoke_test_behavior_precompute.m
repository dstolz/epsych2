function smoke_test_behavior_precompute()
% smoke_test_behavior_precompute
% Standing proof of making psignifit fits ahead of time, off the MATLAB
% thread (behavior.Precompute, behavior.Study.prepare and ParallelFits, the
% job seam of behavior.fit.Psignifit, and Analysis > Precompute in
% epsych.BehaviorAnalysis):
%    1  a fit is slim: Raw serializes to well under 1 MB (psignifit's own
%       psiHandle closes over its ~200 MB grids), its psiHandle gives
%       psignifit's values, the disk cache records its format and holds no
%       large file
%    2  the job seam: fromCounts(Defer) hands back a job on a miss, the fit
%       on a hit, nothing for data it refuses; fitEntry on a background
%       worker makes the entry the MATLAB thread makes
%    3  submit / collect / cancel: submitted, then running (one fit, not
%       two), fitted, cached; a fit asked for while a worker makes it waits
%       for that worker; cancel leaves nothing running
%    4  Study.prepare, isCurrent, isCurrentJob
%    5  Precompute.run: every session current, the numbers a fit made on
%       the MATLAB thread with no cache gives
%    6  Precompute.start: finishes on its own timer; a restart after a
%       settings change cancels the stale fits; HoldFcn holds it; stop
%       cancels
%    7  without a pool (override "serial") fits are made on the MATLAB thread
%    8  Study.results with ParallelFits gives what it gives without, and a
%       Progress that stops keeps only the results already made
%    9  the window: the Analysis menu items, ParallelFits on, automatic
%       precompute on a settings change, Stop Precomputing, Precompute Fits
%       Now, the PrecomputeFits preference written by the menu item only,
%       nothing left running after close
%
% Needs psignifit (https://github.com/wichmann-lab/psignifit); without it
% every group is skipped. The data are drawn fresh each run, so the fits
% are real fits and not cache hits, and the cache files they leave are
% removed. psignifit's coarse grid keeps a fit near a second.
%
%   run('tmp/smoke_test_behavior_precompute.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('epsych.BitMask', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);
if ~behavior.fit.Psignifit.available()
    fprintf('\npsignifit is not installed here: every group skipped (%s).\n', behavior.fit.Psignifit.URL);
    return
end

pid = feature('getpid');
root = fullfile(tempdir, sprintf('epsych_precompute_root_%d', pid));
cache = fullfile(tempdir, sprintf('epsych_precompute_cache_%d', pid));
for d = {root, cache}
    if isfolder(d{1}), rmdir(d{1}, 's'); end
end

PREF = 'epsych2_BehaviorAnalysis';
saved = localSavePrefs(PREF);
fitsBefore = localCacheFiles();
restorePrefs = onCleanup(@() localRestorePrefs(saved));
removeFolders = onCleanup(@() localRemove({root, cache}));
removeFits = onCleanup(@() localRemoveNewFits(fitsBefore));
stopFits = onCleanup(@() behavior.fit.Psignifit.cancel());
noOverride = onCleanup(@() behavior.fit.Psignifit.override(""));
closeWindows = onCleanup(@localCloseWindows);
localCloseWindows();

%% Fixture: five sessions of a 1-up/1-down track, drawn fresh
N = 5;
mkdir(fullfile(root, 'ProjQ', 'Q1'));
day0 = datetime(2026, 10, 1, 9, 0, 0);
seed0 = mod(round(posixtime(datetime('now')) * 1000), 1e6) + mod(pid, 1000) * 1e6;
for i = 1:N
    Data = localObserverData(160, 20, seed0 + i);
    stamp = string(day0 + days(i - 1), 'yyMMdd''T''HHmmss');
    save(fullfile(root, 'ProjQ', 'Q1', sprintf('Q1_%s.mat', stamp)), 'Data');
end
S = behavior.Study(root, Roster = "none", CacheFolder = cache);
S.setSettings(localSettings("norm", 0.5));
keys = S.visibleKeys();

%% 1. A fit is slim
try
    [C, o, info] = localCounts(S, keys(1));
    F = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, o, info, UseCache = false);
    bytes = numel(getByteStreamFromArray(F.Raw));
    results(end+1,:) = check(sprintf('a fit''s Raw serializes to %.0f kB, without psignifit''s grids', bytes / 1e3), ...
        bytes < 1e6);
    data = [C.Levels(:) C.NumYes(:) C.NumTotal(:)];
    data = sortrows(data(data(:, 3) > 0, :), 1);
    full = localQuiet(@() psignifit(data, o));
    x = linspace(min(C.Levels), max(C.Levels), 25);
    results(end+1,:) = check('its psiHandle gives psignifit''s own values', ...
        isequal(full.psiHandle(x), F.Raw.psiHandle(x)));
    folder = behavior.fit.Psignifit.cacheFolder();
    marker = fullfile(folder, "format.txt");
    files = dir(fullfile(folder, 'fit_*.mat'));
    results(end+1,:) = check('the disk cache records its format, and holds no file over 1 MB', ...
        isfile(marker) && strtrim(string(fileread(marker))) == string(behavior.fit.Psignifit.CACHE_FORMAT) ...
        && ~isempty(files) && all([files.bytes] < 1e6));
catch ME
    results(end+1,:) = check(['group 1 threw: ' ME.message], false);
end

%% 2. The job seam
try
    [C2, o2, info2] = localCounts(S, keys(2));
    [F2, job] = behavior.fit.Psignifit.fromCounts(C2.Levels, C2.NumYes, C2.NumTotal, o2, info2, Defer = true);
    results(end+1,:) = check('Defer on a miss: a job, and no fit', ...
        ~isempty(job) && all(isfield(job, {'Key' 'Text' 'Data' 'Options' 'Version'})) ...
        && isnan(F2.Threshold) && contains(F2.Message, "queued"));
    [F1, job1] = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, o, info, Defer = true);
    results(end+1,:) = check('Defer on a hit: the cached fit, no job', ...
        isempty(job1) && isequaln(rmfield(F1, 'Raw'), rmfield(F, 'Raw')));
    [Fr, jr] = behavior.fit.Psignifit.fromCounts(5, 3, 10, o, info, Defer = true);
    results(end+1,:) = check('Defer on data psignifit would refuse: the reason, no job', ...
        isempty(jr) && contains(Fr.Message, "two distinct"));
    fut = parfeval(backgroundPool, @behavior.fit.Psignifit.fitEntry, 1, job);
    wait(fut);
    eW = fetchOutputs(fut);
    eC = behavior.fit.Psignifit.fitEntry(job);
    drop = {'psiHandle' 'timestamp'};
    results(end+1,:) = check('fitEntry on a background worker makes the MATLAB thread''s entry', ...
        eW.Text == eC.Text && isequal(eW.Warnings, eC.Warnings) ...
        && isequaln(localNoHandles(rmfield(eW.Result, drop)), localNoHandles(rmfield(eC.Result, drop))) ...
        && isequal(eW.Result.psiHandle(x), eC.Result.psiHandle(x)));
catch ME
    results(end+1,:) = check(['group 2 threw: ' ME.message], false);
end

%% 3. submit, collect, cancel
try
    [fut, st1] = behavior.fit.Psignifit.submit(job);
    [fut2, st2] = behavior.fit.Psignifit.submit(job);
    results(end+1,:) = check('submit: "submitted", then "running" with the same future', ...
        st1 == "submitted" && st2 == "running" && fut2.ID == fut.ID);
    results(end+1,:) = check('collect while the worker fits: "running"', ...
        behavior.fit.Psignifit.collect(job) == "running");
    Fw = behavior.fit.Psignifit.fromCounts(C2.Levels, C2.NumYes, C2.NumTotal, o2, info2);
    results(end+1,:) = check('a fit asked for meanwhile waits for that worker and takes its fit', ...
        fut.Read && behavior.fit.Psignifit.running() == 0 && isfinite(Fw.Deviance) ...
        && behavior.fit.Psignifit.collect(job) == "fitted");
    [fut3, st3] = behavior.fit.Psignifit.submit(job);
    results(end+1,:) = check('submit once it is fitted: "cached", no future', st3 == "cached" && isempty(fut3));

    [C3, o3, info3] = localCounts(S, keys(3));
    [~, job3] = behavior.fit.Psignifit.fromCounts(C3.Levels, C3.NumYes, C3.NumTotal, o3, info3, Defer = true);
    behavior.fit.Psignifit.submit(job3);
    n = behavior.fit.Psignifit.cancel(job3);
    [st4, msg4] = behavior.fit.Psignifit.collect(job3);
    results(end+1,:) = check('cancel: the fit stops, nothing runs, collect says failed', ...
        n == 1 && behavior.fit.Psignifit.running() == 0 && st4 == "failed" && msg4 ~= "");
catch ME
    results(end+1,:) = check(['group 3 threw: ' ME.message], false);
end

%% 4. Study.prepare, isCurrent, isCurrentJob
try
    k4 = keys(4);
    results(end+1,:) = check('isCurrent before anything is made: false; IsComputing false at rest', ...
        ~S.isCurrent(k4) && ~S.IsComputing);
    [done, job4] = S.prepare(k4);
    results(end+1,:) = check('prepare on a fit not cached: not done, a job naming its session, nothing kept', ...
        ~done && job4.SessionKey == k4 && S.isCurrentJob(job4) && ~S.isCurrent(k4));
    S.result(k4);
    [done2, j2] = S.prepare(k4);
    results(end+1,:) = check('result makes it current; prepare then: done, no job', ...
        S.isCurrent(k4) && done2 && isempty(j2));
    S.setSettings(localSettings("logistic", 0.5));
    results(end+1,:) = check('isCurrentJob is false once the settings change', ~S.isCurrentJob(job4));
    S.setSettings(behavior.Settings());
    [d5, j5] = S.prepare(keys(5));
    results(end+1,:) = check('with the built-in engine prepare makes the result at once', ...
        d5 && isempty(j5) && S.isCurrent(keys(5)));
    S.setSettings(localSettings("norm", 0.5));
catch ME
    results(end+1,:) = check(['group 4 threw: ' ME.message], false);
end

%% 5. Precompute.run
try
    P = behavior.Precompute(S);
    ok = P.run();
    results(end+1,:) = check(sprintf('run: every visible session current (%s)', P.message()), ...
        ok && P.State == "done" && P.Total == N && P.Done == N && P.Failed == 0 ...
        && localAllCurrent(S, keys));
    ok2 = P.run();
    results(end+1,:) = check('run again: nothing made twice', ok2 && P.Done == N && P.Computed == 0);
    R5 = S.result(keys(5));
    [C5, o5, info5] = localCounts(S, keys(5));
    Fn = behavior.fit.Psignifit.fromCounts(C5.Levels, C5.NumYes, C5.NumTotal, o5, info5, UseCache = false);
    Rd = S.session(keys(5)).analyze(S.Settings);
    results(end+1,:) = check('a precomputed result is the one made on the MATLAB thread, fit and all', ...
        isequaln(rmfield(R5.Fit, 'Raw'), rmfield(Fn, 'Raw')) && isequaln(localStrip(R5), localStrip(Rd)));
catch ME
    results(end+1,:) = check(['group 5 threw: ' ME.message], false);
end

%% 6. Precompute.start in the background
try
    S.setSettings(localSettings("logistic", 0.5));
    P.start();
    localWait(P, 120);
    results(end+1,:) = check('start: finishes on its own timer, every session current', ...
        P.State == "done" && P.Computed == N && localAllCurrent(S, keys) && contains(P.message(), "Precomputed"));

    S.setSettings(localSettings("gumbel", 0.5));
    P.start();
    localWaitFor(@() P.Fitting > 0, 20);
    wasFitting = P.Fitting;
    S.setSettings(localSettings("rgumbel", 0.5));
    P.start();
    results(end+1,:) = check('a restart after a settings change cancels the stale fits', ...
        wasFitting > 0 && P.Fitting == 0 && behavior.fit.Psignifit.running() == 0);
    localWait(P, 120);
    results(end+1,:) = check('and finishes under the new settings', P.State == "done" && localAllCurrent(S, keys));

    localHold("set", true);
    P.HoldFcn = @() localHold("get");
    S.setSettings(localSettings("tdist", 0.5));
    P.start();
    pause(1.5);
    results(end+1,:) = check('HoldFcn holds it: nothing starts', ...
        P.State == "held" && P.Fitting == 0 && P.Done == 0 && contains(P.message(), "waits"));
    localHold("set", false);
    localWait(P, 120);
    results(end+1,:) = check('released, it finishes', P.State == "done" && localAllCurrent(S, keys));
    P.HoldFcn = [];

    S.setSettings(localSettings("logn", 0.5));
    P.start();
    localWaitFor(@() P.Fitting > 0, 20);
    P.stop();
    results(end+1,:) = check('stop: stopped, no fit left running', ...
        P.State == "stopped" && P.Fitting == 0 && behavior.fit.Psignifit.running() == 0 ...
        && contains(P.message(), "stopped"));
    delete(P);
catch ME
    results(end+1,:) = check(['group 6 threw: ' ME.message], false);
end

%% 7. Without a pool
try
    behavior.fit.Psignifit.override("serial");
    S.setSettings(localSettings("weibull", 0.5));
    results(end+1,:) = check('override "serial": no pool, not parallel', ...
        isempty(behavior.fit.Psignifit.pool()) && behavior.fit.Psignifit.workers() == 0 ...
        && ~behavior.Precompute.isParallel(S.Settings));
    P2 = behavior.Precompute(S);
    ok = P2.run(keys(1:2));
    results(end+1,:) = check('without a pool the fits are made on the MATLAB thread', ...
        ok && ~P2.Parallel && P2.Done == 2 && localAllCurrent(S, keys(1:2)));
    delete(P2);
    behavior.fit.Psignifit.override("");
catch ME
    behavior.fit.Psignifit.override("");
    results(end+1,:) = check(['group 7 threw: ' ME.message], false);
end

%% 8. Study.results with ParallelFits
try
    S.ParallelFits = true;
    S.setSettings(localSettings("norm", 0.6));
    [T1, R1] = S.results(keys);
    S.ParallelFits = false;
    S.setSettings(localSettings("logistic", 0.6));
    S.setSettings(localSettings("norm", 0.6));
    [T2, R2] = S.results(keys);
    results(end+1,:) = check('results with ParallelFits = results without', ...
        height(T1) == N && isequaln(T1.Threshold, T2.Threshold) ...
        && isequaln(arrayfun(@(r) r.Fit.Threshold, R1), arrayfun(@(r) r.Fit.Threshold, R2)) ...
        && isequaln(arrayfun(@(r) r.Fit.Deviance, R1), arrayfun(@(r) r.Fit.Deviance, R2)));
    S.ParallelFits = true;
    S.setSettings(localSettings("norm", 0.7));
    [~, R3] = S.results(keys, Progress = @(k, n) k <= 2);
    nCurrent = sum(arrayfun(@(k) S.isCurrent(k), keys));
    results(end+1,:) = check(sprintf('a Progress that stops keeps only what was made (%d of %d)', numel(R3), N), ...
        numel(R3) == nCurrent && numel(R3) < N && behavior.fit.Psignifit.running() == 0);
catch ME
    results(end+1,:) = check(['group 8 threw: ' ME.message], false);
end

%% 9. The window
try
    if ispref(PREF, 'PrecomputeFits'), rmpref(PREF, 'PrecomputeFits'); end
    app = epsych.BehaviorAnalysis(root, Visible = false, CacheFolder = string(cache), Roster = "none");
    H = app.H;
    results(end+1,:) = check('Analysis has Precompute Fits Now, Automatically and Stop; the window fits on workers', ...
        isgraphics(H.mnu_precompute) && isgraphics(H.mnu_autoPrecompute) && isgraphics(H.mnu_stopPrecompute) ...
        && H.mnu_autoPrecompute.Checked == "off" && H.mnu_stopPrecompute.Enable == "off" && app.Study.ParallelFits);

    app.setAutoPrecompute(true);
    results(end+1,:) = check('setAutoPrecompute ticks the item and writes no preference', ...
        H.mnu_autoPrecompute.Checked == "on" && ~ispref(PREF, 'PrecomputeFits'));
    % Coarse fits can land while applySettings is still redrawing (a timer
    % runs in a drawnow), so the precompute is asked, not the status line.
    P = app.Precompute;
    app.applySettings(localSettings("norm", 0.8));
    localWait(P, 120);
    results(end+1,:) = check(sprintf('a settings change precomputes every session in the background (%s)', P.message()), ...
        P.State == "done" && P.Computed == N && localAllCurrent(app.Study, keys));

    % Standard-grid fits take seconds: the precompute is surely running.
    app.applySettings(localSettings("logistic", 0.8, "standard"));
    localWaitFor(@() behavior.fit.Psignifit.running() > 0, 20);
    stopOn = H.mnu_stopPrecompute.Enable == "on";
    app.stopPrecompute();
    results(end+1,:) = check('Stop Precomputing: enabled while it runs; stops it, nothing left running', ...
        stopOn && H.mnu_stopPrecompute.Enable == "off" && behavior.fit.Psignifit.running() == 0 ...
        && P.State == "stopped" && contains(string(H.status.Text), "stopped"));

    cb = H.mnu_autoPrecompute.MenuSelectedFcn;
    cb(H.mnu_autoPrecompute, []);
    results(end+1,:) = check('the menu item turns it off and remembers that (PrecomputeFits)', ...
        H.mnu_autoPrecompute.Checked == "off" && ispref(PREF, 'PrecomputeFits') ...
        && ~logical(getpref(PREF, 'PrecomputeFits')));

    app.applySettings(localSettings("logistic", 0.8));
    n = app.precomputeFits();
    localWait(P, 120);
    results(end+1,:) = check('Precompute Fits Now makes every visible session current, and says so', ...
        n == N && P.State == "done" && localAllCurrent(app.Study, keys) ...
        && contains(string(H.status.Text), "Precomputed"));

    app.applySettings(localSettings("gumbel", 0.8, "standard"));
    app.precomputeFits();
    localWaitFor(@() behavior.fit.Psignifit.running() > 0, 20);
    delete(app);
    results(end+1,:) = check('closing the window cancels its fits and its timer', ...
        behavior.fit.Psignifit.running() == 0 && isempty(timerfind('Name', 'behavior.Precompute')));
catch ME
    results(end+1,:) = check(['group 9 threw: ' ME.message], false);
end

localReport(results);
delete(closeWindows);
delete(noOverride);
delete(stopFits);
delete(removeFits);
delete(removeFolders);
delete(restorePrefs);
end


% ---------------------------------------------------------------------------
function row = check(label, tf)
row = {char(label), logical(tf)};
end

function localReport(results)
fprintf('\n');
nFail = 0;
for k = 1:size(results, 1)
    if results{k,2}
        tag = 'PASS';
    else
        tag = 'FAIL';
        nFail = nFail + 1;
    end
    fprintf('  %s  %s\n', tag, results{k,1});
end
fprintf('smoke_test_behavior_precompute: %d checks, %d failed\n', size(results, 1), nFail);
if nFail > 0
    error('smoke_test_behavior_precompute:Failed', '%d check(s) failed', nFail);
end
end

function s = localSettings(sigmoid, pc, grid)
% psignifit, on its coarse grid unless told: a fit near a second.
arguments
    sigmoid (1,1) string
    pc (1,1) double
    grid (1,1) string = "coarse"
end
s = behavior.Settings();
s.Fit.Engine = "psignifit";
p = s.Psignifit;
p.Grid = grid;
p.Sigmoid = sigmoid;
p.ThresholdPC = pc;
s.Psignifit = p;
end

function [C, o, info] = localCounts(S, key)
% What behavior.Session.fit hands psignifit for this session.
st = S.session(key).staircase(S.Settings);
C = st.psychometricCounts(IncludeAborts = S.Settings.IncludeAborts);
[o, info] = S.Settings.psignifitOptions(CatchFalseAlarmRate = C.CatchFalseAlarmRate);
end

function R = localStrip(R)
% A result without what differs between two makings of the same one: the
% time taken, and the fit's function handle (equal values, not one handle).
R = rmfield(R, 'Elapsed');
R.Fit = rmfield(R.Fit, 'Raw');
end

function out = localQuiet(fcn)
% What a call returned, with what it printed swallowed.
assert(isa(fcn, 'function_handle'));
out = [];
evalc('out = fcn();');
end

function out = localHold(op, value)
% The HoldFcn's answer, settable while the precompute runs.
persistent held
if isempty(held), held = false; end
if op == "set", held = value; end
out = held;
end

function v = localNoHandles(v)
% Function handles as their text: two psignifit calls make equal handles
% that are never the same handle.
if isa(v, 'function_handle')
    v = func2str(v);
elseif isstruct(v)
    for k = 1:numel(v)
        f = fieldnames(v);
        for j = 1:numel(f)
            v(k).(f{j}) = localNoHandles(v(k).(f{j}));
        end
    end
elseif iscell(v)
    v = cellfun(@localNoHandles, v, 'UniformOutput', false);
end
end

function tf = localAllCurrent(S, keys)
tf = all(arrayfun(@(k) S.isCurrent(k), keys));
end

function localWait(P, timeout)
% Let the timer run until the precompute has finished.
t = tic;
while any(P.State == ["running" "held"]) && toc(t) < timeout
    pause(0.1);
end
end

function localWaitFor(fcn, timeout)
t = tic;
while ~fcn() && toc(t) < timeout
    pause(0.1);
end
end

function names = localCacheFiles()
files = dir(fullfile(behavior.fit.Psignifit.cacheFolder(), 'fit_*.mat'));
names = {files.name};
end

function localRemoveNewFits(before)
% The cache files this run's fresh data made: no later run can hit them.
try
    folder = behavior.fit.Psignifit.cacheFolder();
    now_ = localCacheFiles();
    new = setdiff(now_, before);
    for k = 1:numel(new)
        delete(fullfile(folder, new{k}));
    end
catch
end
end

function s = localSavePrefs(group)
s = struct('group', group, 'existed', ispref(group), 'values', struct());
if s.existed
    s.values = getpref(group);
end
end

function localRestorePrefs(s)
try
    if ispref(s.group), rmpref(s.group); end
    names = fieldnames(s.values);
    for j = 1:numel(names)
        setpref(s.group, names{j}, s.values.(names{j}));
    end
catch
end
end

function localRemove(folders)
for f = folders
    try
        if isfolder(f{1}), rmdir(f{1}, 's'); end
    catch
    end
end
end

function localCloseWindows()
app = epsych.BehaviorAnalysis.find();
while ~isempty(app)
    delete(app);
    app = epsych.BehaviorAnalysis.find();
end
end

function DATA = localObserverData(nTrials, mu, seed)
% A symmetric 1-up/1-down track on a positive-dB Depth, converging on mu, with
% a catch trial every sixth and the odd abort; shaped like RUNTIME.TRIALS.DATA.
rng(seed);
HIT   = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS  = bitset(uint32(0), uint32(epsych.BitMask.Miss));
CR    = bitset(uint32(0), uint32(epsych.BitMask.CorrectReject));
FA    = bitset(uint32(0), uint32(epsych.BitMask.FalseAlarm));
ABORT = bitset(uint32(0), uint32(epsych.BitMask.Abort));
ttBit = uint32(epsych.BitMask.TrialType_0);

depth = 40;
step = 2;
t0 = datetime(2026, 10, 1, 9, 0, 0);
DATA = struct('Depth', cell(1, nTrials), 'RespCode', [], 'TrialType', [], ...
    'TrialIndex', [], 'TrialID', [], 'computerTimestamp', [], 'isTest', []);
for k = 1:nTrials
    if mod(k, 6) == 0
        rc = CR;
        if rand < 0.15, rc = FA; end
        tt = 1;
    elseif rand < 0.03
        rc = ABORT;
        tt = 0;
    else
        tt = 0;
        pHit = 1 / (1 + exp(-0.8 * (depth - mu)));
        rc = MISS;
        if rand() < pHit
            rc = HIT;
        end
    end
    DATA(k) = struct('Depth', depth, 'RespCode', bitset(rc, ttBit + tt), 'TrialType', tt, ...
        'TrialIndex', k, 'TrialID', tt + 1, 'computerTimestamp', t0 + seconds(8 * k), ...
        'isTest', false);
    if tt == 0 && rc == HIT
        depth = max(2, depth - step);
    elseif tt == 0 && rc == MISS
        depth = min(60, depth + step);
    end
end
end
