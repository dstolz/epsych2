function smoke_test_history_perf()
% smoke_test_history_perf()
% Report per-update cost for gui.components.History. This is a measurement harness, not
% a pass/fail test: it fails only if the harness itself breaks.
%
% Sections:
%   1. Per-update wall time vs. trial count, with and without the row cache.
%   2. Logging attribution: GLogVerbosity = Inf (default) vs. a finite level.
%      With the default, every vprintf record pays dbstack('-completenames')
%      plus a .error_logs write -- a fixed per-trial cost independent of N.
%   3. Raw uitable write shapes: full replace vs. append vs. prepend, to
%      settle whether a subscripted append can beat a single full assignment.
%
% Graphics marshalling is understated in a headless run, so quote numbers
% from a session with a visible figure.
%
%   matlab -batch "run('tmp/smoke_test_history_perf.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % +psychophysics/FakeHistoryPsych.m merges into psychophysics package

PREF_GROUP = 'epsych2_gui_History';
TAG = 'smokeHistPerf';
cleanupPrefs(PREF_GROUP, {TAG});
cleanupObj = onCleanup(@() cleanupPrefs(PREF_GROUP, {TAG}));

VISIBLE = 'on'; % 'on' exercises real marshalling; a headless run understates it
NREP    = 20;   % single-trial appends timed per configuration

fprintf('\n=== gui.components.History update cost ===\n');
fprintf('MATLAB %s | visible=%s | reps=%d\n\n', version('-release'), VISIBLE, NREP);

%% 1. Per-update cost vs. trial count -------------------------------------
% Baseline before the update-speed work, for comparison (R2024b, visible):
%   N=10 145.1 | N=50 111.4 | N=200 120.6 | N=1000 157.7 ms
Ns = [10 50 200 1000];
fprintf('%-8s %-14s %-14s\n','N','padded(ms)','exact rows(ms)');
fprintf('%s\n',repmat('-',1,40));
for ni = 1:numel(Ns)
    padded = timeAppends(Ns(ni), 50, NREP, VISIBLE, TAG);
    exact  = timeAppends(Ns(ni),  1, NREP, VISIBLE, TAG);
    fprintf('%-8d %-14.3f %-14.3f\n', Ns(ni), padded, exact);
end

%% 2. Logging attribution --------------------------------------------------
% GLogVerbosity is the documented public control for log verbosity; see
% granary.isEnabled, which is the only other place it is interpreted.
global GLogVerbosity
savedLog = GLogVerbosity;
restoreLog = onCleanup(@() setGlobalLogVerbosity(savedLog));

fprintf('\n=== logging attribution (N=200) ===\n');
GLogVerbosity = Inf;
tInf = timeAppends(200, 50, NREP, VISIBLE, TAG);
GLogVerbosity = 2;
tFin = timeAppends(200, 50, NREP, VISIBLE, TAG);
GLogVerbosity = savedLog;
fprintf('GLogVerbosity=Inf : %7.3f ms/update\n', tInf);
fprintf('GLogVerbosity=2   : %7.3f ms/update\n', tFin);
fprintf('logging cost      : %7.3f ms/update (%.1f%%)\n', tInf-tFin, 100*(tInf-tFin)/max(tInf,eps));

%% 3. Raw uitable write shapes --------------------------------------------
fprintf('\n=== raw uitable write shapes (ms, incl. drawnow) ===\n');
fprintf('%-8s %-12s %-12s %-12s\n','N','replace','append','prepend');
fprintf('%s\n',repmat('-',1,46));
for N = [200 1000]
    f = uifigure('Visible',VISIBLE,'Position',[100 100 700 500]);
    c = onCleanup(@() close(f));
    C = repmat({'aaaa','bbbb','cccc','dddd','eeee','ffff'},N,1);
    t = uitable(f,'Data',C,'Unit','Normalized','Position',[0 0 1 1]);
    row = {'zzzz','zzzz','zzzz','zzzz','zzzz','zzzz'};
    drawnow

    tr = timeit_(@() setFull(t,C), NREP);
    ta = timeit_(@() setAppend(t,row), NREP);
    t.Data = C;
    tp = timeit_(@() setPrepend(t,row), NREP);

    fprintf('%-8d %-12.3f %-12.3f %-12.3f\n', N, tr, ta, tp);
    clear c
end

fprintf('\nsmoke_test_history_perf: done\n');
end


function ms = timeAppends(N, blockSize, nrep, visible, tag)
% Median wall time of nrep single-trial appends driven through the NewData
% listener, each followed by drawnow so graphics cost is included.
% blockSize of 1 renders an exact row count, i.e. padding disabled.
P = psychophysics.FakeHistoryPsych('FreqHz');
P.setData(makeData(N));
f = uifigure('Visible',visible,'Position',[100 100 700 500],'Tag','SmokeHistPerf');
c = onCleanup(@() close(f));
H = gui.components.History(P, f, PreferenceTag=tag);
H.RowBlockSize = blockSize;
H.ParametersOfInterest = {'FreqHz','LevelDB','RespLatency'};
H.update();
drawnow

t = nan(1,nrep);
for k = 1:nrep
    trial = makeData(1);
    trial.computerTimestamp = datetime('now') + seconds(N+k);
    tic
    P.appendTrials(trial);
    drawnow
    t(k) = toc;
end
ms = median(t)*1e3;
delete(H);
clear c
end


function ms = timeit_(fcn, nrep)
t = nan(1,nrep);
for k = 1:nrep
    tic; fcn(); drawnow; t(k) = toc;
end
ms = median(t)*1e3;
end

function setFull(t,C),    t.Data = C; end
function setAppend(t,r),  t.Data(end+1,:) = r; end
function setPrepend(t,r), t.Data = [r; t.Data]; end

function setGlobalLogVerbosity(v)
global GLogVerbosity
GLogVerbosity = v;
end


function D = makeData(n)
% Per-trial DATA struct array shaped like RUNTIME.TRIALS.DATA.
D = struct([]);
for k = 1:n
    D(k).TrialID = mod(k-1,4)+1;
    D(k).RespCode = uint32(2^mod(k,5));
    D(k).computerTimestamp = datetime('now') + seconds(k);
    D(k).FreqHz = 1000*2^mod(k,5);
    D(k).LevelDB = 30 + 5*mod(k,7);
    D(k).RespLatency = 100 + 3*mod(k,11);
end
end

function cleanupPrefs(group, tags)
for k = 1:numel(tags)
    tag = matlab.lang.makeValidName(tags{k});
    if ispref(group, tag)
        rmpref(group, tag);
    end
end
end
