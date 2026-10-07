function smoke_test_behavior_sessionview()
% smoke_test_behavior_sessionview
% Standing proof of gui.behavior.SessionView, the Session tab of
% epsych.BehaviorAnalysis, headless (hidden uifigure):
%   - it hosts the session's psychophysics.Staircase in its own grid cell and
%     labels it from the session;
%   - showing another session replaces the staircase object (no leak);
%   - a per-session window override from the Study, or typed into the view,
%     redraws and shows as such; text the window cannot read is refused;
%   - a change made through the staircase's right-click settings (simulated
%     by setting the SetObservable property) becomes the Study's Settings,
%     without rebuilding the plot, and an unchanged value does nothing;
%   - clearing and deleting release everything.
%
%   run('tmp/smoke_test_behavior_sessionview.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('epsych.BitMask', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);
pid = feature('getpid');
root = fullfile(tempdir, sprintf('epsych_sessionview_smoke_%d', pid));
cache = fullfile(tempdir, sprintf('epsych_sessionview_cache_%d', pid));
store = fullfile(tempdir, sprintf('epsych_sessionview_store_%d', pid));
if isfolder(root), rmdir(root, 's'); end
mkdir(fullfile(root, 'P', 'S1'));
cleanup = onCleanup(@() localCleanup({root, cache, store}, 'SessionView smoke'));

%% Fixture: one subject, three sessions
day0 = datetime(2026, 10, 1, 9, 0, 0);
for i = 1:3
    Data = localObserverData(80, 20 + 2 * i, 300 + i);
    stamp = string(day0 + days(i - 1), 'yyMMdd''T''HHmmss');
    save(fullfile(root, 'P', 'S1', sprintf('S1_%s_Pre.mat', stamp)), 'Data');
end
S = behavior.Study(root, Store = store, Roster = "none", CacheFolder = cache);
keys = S.visibleKeys();

f = uifigure('Visible', 'off', 'Name', 'SessionView smoke');
g = uigridlayout(f, [1 1]);

%% 1. Build and show
try
    V = gui.behavior.SessionView(g, S);
    results(end+1,:) = check('an empty view says so', strcmp(V.H.title.Text, 'No session') && isempty(V.Staircase));
    V.show(keys(1));
    S1 = V.Staircase;
    results(end+1,:) = check('show builds the session''s staircase', ...
        isa(S1, 'psychophysics.Staircase') && isvalid(S1) && S1.trialCount == 80);
    results(end+1,:) = check('the staircase is drawn into the view''s axes', ...
        ~isempty(findobj(V.H.stairAxes, 'Type', 'line')) || ~isempty(findobj(V.H.stairAxes, 'Type', 'scatter')));
    results(end+1,:) = check('the staircase is labelled from the session', ...
        startsWith(string(V.H.stairAxes.Title.String), "S1") && contains(string(V.H.stairAxes.YLabel.String), "Depth"));
    results(end+1,:) = check('the title names subject, date and tag', ...
        contains(V.H.title.Text, 'S1') && contains(V.H.title.Text, 'Pre'));
    results(end+1,:) = check('the summary reports the thresholds and the window', ...
        any(contains(string(V.H.summary.Value), "Reversal threshold")) && any(contains(string(V.H.summary.Value), "Window: all")));
    results(end+1,:) = check('the metrics table is filled', size(V.H.metrics.Data, 1) > 0);
    results(end+1,:) = check('the window field shows the settings'' window as a placeholder', ...
        isempty(V.H.window.Value) && strcmp(V.H.window.Placeholder, 'all'));
    results(end+1,:) = check('Review and Copy are enabled', ...
        strcmp(V.H.btnReview.Enable, 'on') && strcmp(V.H.btnCopy.Enable, 'on'));
    if exist('behavior.Plot', 'class') == 8
        results(end+1,:) = check('the psychometric fit is drawn', ~isempty(V.H.fitAxes.Children));
    end
catch ME
    results(end+1,:) = check(['group 1: ' ME.message], false);
end

%% 2. Another session replaces the staircase
try
    S1 = V.Staircase;
    V.show(keys(2));
    results(end+1,:) = check('the previous staircase object is deleted', ~isvalid(S1));
    results(end+1,:) = check('a new one is drawn', isvalid(V.Staircase) && V.Staircase ~= S1 && V.Result.Key == keys(2));
    results(end+1,:) = check('the axes survived the swap', isgraphics(V.H.stairAxes));
catch ME
    results(end+1,:) = check(['group 2: ' ME.message], false);
end

%% 3. Windows: from the Study and from the field
try
    S.setWindow(keys(2), "3-83");
    results(end+1,:) = check('a Study window override reaches the view', ...
        strcmp(V.H.window.Value, '3-83') && V.Result.Window == "3-83" && contains(V.H.windowHint.Text, 'override'));
    results(end+1,:) = check('... and the staircase was rebuilt on it', V.Result.NumIncluded < 80);
    V.H.window.Value = 'last 20';
    V.H.window.ValueChangedFcn(V.H.window, []);
    results(end+1,:) = check('typing a window sets the override', S.windowFor(keys(2)) == "last 20" && V.Result.Window == "last 20");
    V.H.window.Value = 'banana';
    V.H.window.ValueChangedFcn(V.H.window, []);
    results(end+1,:) = check('unreadable text is refused and the field put back', ...
        S.windowFor(keys(2)) == "last 20" && strcmp(V.H.window.Value, 'last 20'));
    V.H.window.Value = '';
    V.H.window.ValueChangedFcn(V.H.window, []);
    results(end+1,:) = check('clearing the field clears the override', S.windowFor(keys(2)) == "" && V.Result.Window == "all");
catch ME
    results(end+1,:) = check(['group 3: ' ME.message], false);
end

%% 4. The plot menu is one more editor of the Settings
try
    n = containers.Map({'SettingsChanged'}, {0});
    L = addlistener(S, 'SettingsChanged', @(~,~) localBump(n, 'SettingsChanged'));
    St = V.Staircase;
    hashBefore = V.Result.SettingsHash;
    St.ThresholdFormula = "GeometricMean";          % what the right-click menu does
    results(end+1,:) = check('a menu change becomes the Study''s setting', ...
        S.Settings.Staircase.ThresholdFormula == "GeometricMean" && n('SettingsChanged') == 1);
    results(end+1,:) = check('the staircase that was changed is kept, not rebuilt', isvalid(St) && V.Staircase == St);
    results(end+1,:) = check('the view''s result follows the new settings', V.Result.SettingsHash ~= hashBefore);
    St.ThresholdFromLastNReversals = 4;
    results(end+1,:) = check('a second menu change too', S.Settings.Staircase.ThresholdFromLastNReversals == 4 && n('SettingsChanged') == 2);
    St.ThresholdFromLastNReversals = 4;
    results(end+1,:) = check('the value already held changes nothing', n('SettingsChanged') == 2);
    s = S.Settings;
    s.Staircase.ThresholdFormula = "Mean";
    S.setSettings(s);
    results(end+1,:) = check('a Settings change from elsewhere rebuilds the staircase on it', ...
        isvalid(V.Staircase) && V.Staircase ~= St && V.Staircase.ThresholdFormula == "Mean" && V.Staircase.ThresholdFromLastNReversals == 4);
    delete(L);
catch ME
    results(end+1,:) = check(['group 4: ' ME.message], false);
end

%% 5. Clear and delete
try
    V.copyValues();
    V.show("");
    results(end+1,:) = check('clearing releases the staircase and empties the panel', ...
        isempty(V.Staircase) && strcmp(V.H.title.Text, 'No session') && strcmp(V.H.btnReview.Enable, 'off'));
    V.show(keys(3));
    St = V.Staircase;
    root_ = V.H.root;
    delete(V);
    results(end+1,:) = check('deleting the view deletes its staircase and graphics', ~isvalid(St) && ~isgraphics(root_));
    S.setSettings(behavior.Settings());
    results(end+1,:) = check('a Study event after deletion is harmless', true);
catch ME
    results(end+1,:) = check(['group 5: ' ME.message], false);
end

%% Summary
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
fprintf('smoke_test_behavior_sessionview: %d checks, %d failed\n', size(results, 1), nFail);
if nFail > 0
    error('smoke_test_behavior_sessionview:Failed', '%d check(s) failed', nFail);
end
end



function row = check(label, tf)
row = {char(label), logical(tf)};
end

function m = localBump(m, name)
m(name) = m(name) + 1;
end

function DATA = localObserverData(nTrials, mu, seed)
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

function localCleanup(folders, figName)
try
    delete(findall(groot, 'Type', 'figure', 'Name', figName));
catch
end
for f = folders
    try
        if isfolder(f{1}), rmdir(f{1}, 's'); end
    catch
    end
end
end
