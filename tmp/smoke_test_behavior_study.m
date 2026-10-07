function smoke_test_behavior_study()
% smoke_test_behavior_study
% Standing proof of the across-session layer of the offline behavioral
% analysis: behavior.Aggregate (one row per result, joined with the catalog,
% facet-ready) and behavior.Stats.describe (descriptive only, per session or
% per subject, a seeded bootstrap that leaves the global random stream as it
% found it). behavior.Study joins this file in milestone M4.
%
% Fixture: two subjects, six sessions each -- three "Pre" sessions from a
% simulated observer with threshold 20 and three "Post" with threshold 26 --
% saved as Data-only files under <root>/ProjX/<Subject>/.
%
%   run('tmp/smoke_test_behavior_study.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('epsych.BitMask', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);

pid = feature('getpid');
root = fullfile(tempdir, sprintf('epsych_behavior_study_smoke_%d', pid));
cache = fullfile(tempdir, sprintf('epsych_behavior_study_cache_%d', pid));
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
cleanup = onCleanup(@() localCleanup(root, cache));

%% Fixture
subjects = ["S1" "S2"];
day0 = datetime(2026, 10, 1, 9, 0, 0);
k = 0;
for s = subjects
    folder = fullfile(root, 'ProjX', char(s));
    mkdir(folder);
    for i = 1:6
        k = k + 1;
        if i <= 3
            tag = "Pre";  mu = 20;
        else
            tag = "Post"; mu = 26;
        end
        Data = localObserverData(80, mu, 100 + k);
        stamp = string(day0 + days(i - 1), 'yyMMdd''T''HHmmss');
        save(fullfile(folder, sprintf('%s_%s_%s.mat', s, stamp, tag)), 'Data');
    end
end

cat = behavior.Catalog(root, CacheFolder = cache);
cat.scan();
settings = behavior.Settings();
R = cell(height(cat.Sessions), 1);
for i = 1:height(cat.Sessions)
    sess = behavior.Session.load(cat.Sessions(i, :), Root = root);
    R{i} = sess.analyze(settings);
end
f1 = behavior.Facet("tag", Index = 1);

%% 1. Aggregate.thresholds
try
    T = behavior.Aggregate.thresholds(R, cat.Sessions);
    results(end+1,:) = check('one row per result, in the results'' order', ...
        height(T) == 12 && isequal(string(T.Key), reshape(string(cellfun(@(r) r.Key, R, 'UniformOutput', false)), [], 1)));
    need = ["Key" "Project" "ProjectPath" "Subject" "Tags" "TagText" "NumTags" "Tag1" "Start" "Date" ...
        "SessionOrdinal" "DaysSinceFirst" "Parameter" "Unit" "Window" "NumIncluded" ...
        "Threshold" "ThresholdStd" "ReversalCount" "FitThreshold" "FitConverged" "DPrime" "APrime" ...
        "HitRate" "FARate" "AbortRate" "NumTrials" "QC" "Messages" "SettingsHash" ...
        "SubjectSex" "Paradigm" "Hidden" "Window" "Comment"];
    results(end+1,:) = check('the table carries identity, numbers, facet and project columns', ...
        all(ismember(need, string(T.Properties.VariableNames))));
    results(end+1,:) = check('every valueColumns name is a column', ...
        all(ismember(behavior.Aggregate.valueColumns().Name, string(T.Properties.VariableNames))));
    results(end+1,:) = check('the join carries Project and Subject from the catalog', ...
        all(T.Project == "ProjX") && all(ismember(T.Subject, subjects)));
    results(end+1,:) = check('Tag1 is the first tag', all(ismember(T.Tag1, ["Pre" "Post"])) && sum(T.Tag1 == "Pre") == 6);
    ord = arrayfun(@(s) isequal(sort(T.SessionOrdinal(T.Subject == s))', 1:6), subjects);
    dys = arrayfun(@(s) isequal(sort(T.DaysSinceFirst(T.Subject == s))', 0:5), subjects);
    results(end+1,:) = check('SessionOrdinal runs 1..6 by Start for each subject', all(ord));
    results(end+1,:) = check('DaysSinceFirst runs 0..5 for each subject', all(dys));
    results(end+1,:) = check('thresholds are finite and near the observers'' thresholds', ...
        all(isfinite(T.Threshold)) && median(T.Threshold(T.Tag1 == "Pre")) < median(T.Threshold(T.Tag1 == "Post")));
    results(end+1,:) = check('QC is a joined string column, Messages likewise', ...
        isstring(T.QC) && isstring(T.Messages));
    results(end+1,:) = check('a tag facet reads the table', isequal(f1.values(T), T.Tag1));

    T0 = behavior.Aggregate.thresholds(R);
    results(end+1,:) = check('without a sessions table the identity comes from the results', ...
        height(T0) == 12 && all(T0.Project == "ProjX") && all(T0.Tag1 == T.Tag1) && all(T0.ProjectPath == ""));
    E = behavior.Aggregate.thresholds({});
    results(end+1,:) = check('no results give an empty table with the same columns', ...
        height(E) == 0 && isempty(setdiff(string(T.Properties.VariableNames), string(E.Properties.VariableNames))));

    S2 = cat.Sessions;
    S2.Group_Treatment = repmat("Sham", height(S2), 1);
    S2.Group_Treatment(S2.Subject == "S2") = "Lesion";
    S2.Hidden = false(height(S2), 1);
    S2.Hidden(1) = true;
    S2.Comment = repmat("", height(S2), 1);
    S2.Comment(2) = "noisy";
    S2.Window = repmat("", height(S2), 1);
    Tg = behavior.Aggregate.thresholds(R, S2);
    fm = behavior.Facet("manual", Name = "Treatment");
    results(end+1,:) = check('grouping, Hidden and Comment columns ride along from the sessions table', ...
        ismember("Group_Treatment", string(Tg.Properties.VariableNames)) ...
        && isequal(fm.values(Tg), Tg.Group_Treatment) ...
        && sum(Tg.Group_Treatment == "Lesion") == 6 && sum(Tg.Hidden) == 1 && sum(Tg.Comment == "noisy") == 1);
catch ME
    results(end+1,:) = check(['group 1: ' ME.message], false);
end

%% 2. Aggregate.bySubject
try
    T = behavior.Aggregate.thresholds(R, cat.Sessions);
    S = behavior.Aggregate.bySubject(T, "Threshold", GroupBy = f1);
    results(end+1,:) = check('one row per subject and level', height(S) == 4 && all(S.N == 3));
    [levels, ~] = f1.order(T);
    results(end+1,:) = check('levels in the facet''s order within each subject', ...
        isequal(S.Level', [reshape(levels, 1, []) reshape(levels, 1, [])]));
    results(end+1,:) = check('median, mean, first and last are finite', ...
        all(isfinite([S.Median; S.Mean; S.First; S.Last])));
    S0 = behavior.Aggregate.bySubject(T, "Threshold");
    results(end+1,:) = check('without a facet, one row per subject over all sessions', ...
        height(S0) == 2 && all(S0.N == 6) && all(S0.Level == "(all)"));
    results(end+1,:) = check('an unknown column is refused', ...
        throwsWith(@() behavior.Aggregate.bySubject(T, "Banana"), 'behavior:Aggregate:UnknownColumn'));
catch ME
    results(end+1,:) = check(['group 2: ' ME.message], false);
end

%% 3. Stats.describe
try
    T = behavior.Aggregate.thresholds(R, cat.Sessions);
    D = behavior.Stats.describe(T, "Threshold", GroupBy = f1);
    results(end+1,:) = check('one row per level, six sessions each', height(D) == 2 && all(D.N == 6));
    pre = D(D.Level == "Pre", :);
    post = D(D.Level == "Post", :);
    results(end+1,:) = check('Post sits above Pre', post.Mean > pre.Mean && post.Median > pre.Median);
    results(end+1,:) = check('quartiles bracket the median; SEM is SD/sqrt(N)', ...
        all(D.Q1 <= D.Median & D.Median <= D.Q3) && all(abs(D.SEM - D.SD ./ sqrt(D.N)) < 1e-12));
    results(end+1,:) = check('no CI unless asked', all(isnan(D.CILo)) && all(isnan(D.CIHi)));

    Ds = behavior.Stats.describe(T, "Threshold", GroupBy = f1, Unit = "subject");
    results(end+1,:) = check('per subject: two values per level', height(Ds) == 2 && all(Ds.N == 2));
    results(end+1,:) = check('UserData says what was described', ...
        Ds.Properties.UserData.Unit == "subject" && Ds.Properties.UserData.Facet == "tag:1");

    g = RandStream.getGlobalStream();
    before = g.State;
    Db = behavior.Stats.describe(T, "Threshold", GroupBy = f1, BootstrapCI = true, NumBoot = 300, Seed = 7);
    after = g.State;
    results(end+1,:) = check('a bootstrap CI brackets the mean where N allows', ...
        all(isfinite(Db.CILo)) && all(Db.CILo <= Db.Mean & Db.Mean <= Db.CIHi));
    results(end+1,:) = check('the bootstrap leaves the global stream as it found it', isequal(before, after));
    Db2 = behavior.Stats.describe(T, "Threshold", GroupBy = f1, BootstrapCI = true, NumBoot = 300, Seed = 7);
    results(end+1,:) = check('the same seed gives the same interval', isequaln(Db, Db2));
    Dbs = behavior.Stats.describe(T, "Threshold", GroupBy = f1, BootstrapCI = true, NumBoot = 300, Unit = "subject");
    results(end+1,:) = check('too few values: no interval, not a made-up one', all(isnan(Dbs.CILo)));

    s = behavior.Stats.sentence(Db);
    results(end+1,:) = check('sentence names the levels, the unit and the CI', ...
        contains(s, "Pre n=6") && contains(s, "Post n=6") && contains(s, "per session") && contains(s, "95% CI"));
    results(end+1,:) = check('an unknown column is refused', ...
        throwsWith(@() behavior.Stats.describe(T, "Banana"), 'behavior:Stats:UnknownColumn'));
    E = behavior.Stats.describe(behavior.Aggregate.thresholds({}), "Threshold");
    results(end+1,:) = check('an empty table describes without throwing', istable(E) && isstring(behavior.Stats.sentence(E)));
catch ME
    results(end+1,:) = check(['group 3: ' ME.message], false);
end

%% 4. Study: the headless app state
try
    store = fullfile(tempdir, sprintf('epsych_behavior_study_store_%d', pid));
    S = behavior.Study(root, Store = store, Roster = "none", CacheFolder = cache);
    results(end+1,:) = check('Study scans the root and opens an empty project', ...
        height(S.Catalog.Sessions) == 12 && isa(S.Project, 'behavior.Project') && ~S.Project.Dirty);
    T = S.sessions();
    results(end+1,:) = check('sessions() carries the project columns', ...
        height(T) == 12 && all(ismember(["Hidden" "Window" "Comment"], string(T.Properties.VariableNames))));
    keys = reshape(string(T.Key), 1, []);

    ev = containers.Map({'SelectionChanged','SettingsChanged','ProjectChanged','ResultsChanged','CatalogChanged','Busy'}, ...
        {0, 0, 0, 0, 0, 0});
    L = [addlistener(S, 'SelectionChanged', @(~,~) localBump(ev, 'SelectionChanged')), ...
         addlistener(S, 'SettingsChanged',  @(~,~) localBump(ev, 'SettingsChanged')), ...
         addlistener(S, 'ProjectChanged',   @(~,~) localBump(ev, 'ProjectChanged')), ...
         addlistener(S, 'ResultsChanged',   @(~,~) localBump(ev, 'ResultsChanged')), ...
         addlistener(S, 'CatalogChanged',   @(~,~) localBump(ev, 'CatalogChanged')), ...
         addlistener(S, 'Busy',             @(~,~) localBump(ev, 'Busy'))];

    S.select(keys(1:4));
    results(end+1,:) = check('select sets the checked keys and announces it', ...
        isequal(S.Selection, keys(1:4)) && ev('SelectionChanged') == 1);
    results(end+1,:) = check('select refuses an unknown key', ...
        throwsWith(@() S.select("nope.mat"), 'behavior:Study:UnknownKey'));

    [T1, R1] = S.results();
    results(end+1,:) = check('results() analyses the checked sessions', ...
        height(T1) == 4 && numel(R1) == 4 && ev('ResultsChanged') == 1 && ev('Busy') >= 2);
    T1b = S.results();
    results(end+1,:) = check('a second results() comes from the memo', ...
        isequaln(T1, T1b) && ev('ResultsChanged') == 1);
    r1 = S.result(keys(1));
    r1b = S.result(keys(1));
    results(end+1,:) = check('result(key) is memoized (same Elapsed)', isequaln(r1, r1b));

    s = S.Settings;
    s.Window = "20+";
    S.setSettings(s);
    r1c = S.result(keys(1));
    results(end+1,:) = check('setSettings forgets results: the new window applies', ...
        ev('SettingsChanged') == 1 && r1c.NumIncluded == r1.NumIncluded - 19 && r1c.Window == "20+");
    S.results();
    results(end+1,:) = check('... and results() computes again', ev('ResultsChanged') == 2);

    r2 = S.result(keys(2));
    S.setWindow(keys(1), "3-83");
    r1d = S.result(keys(1));
    results(end+1,:) = check('a per-session window override is used and announced', ...
        r1d.Window == "3-83" && ev('ProjectChanged') >= 1);
    results(end+1,:) = check('... and leaves the other sessions'' results memoized', ...
        isequaln(S.result(keys(2)), r2));
    results(end+1,:) = check('the override is visible through windowFor and sessions()', ...
        S.windowFor(keys(1)) == "3-83" && any(S.sessions().Window == "3-83"));

    S.hide(keys(3));
    results(end+1,:) = check('hide takes a session out of sessions() and visibleKeys()', ...
        height(S.sessions()) == 11 && ~ismember(keys(3), S.visibleKeys()) ...
        && height(S.sessions(IncludeHidden = true)) == 12 && S.isHidden(keys(3)));

    S.addGrouping("Treatment", ["Sham" "Lesion"]);
    S.assign("Treatment", "S2", "Lesion");
    S.assign("Treatment", "S1", "Sham");
    Tg = S.sessions();
    fm = behavior.Facet("manual", Name = "Treatment");
    results(end+1,:) = check('a grouping becomes a Group_ column the manual facet reads', ...
        ismember("Group_Treatment", string(Tg.Properties.VariableNames)) ...
        && all(fm.values(Tg(Tg.Subject == "S2", :)) == "Lesion") && all(fm.values(Tg(Tg.Subject == "S1", :)) == "Sham"));
    Tr = S.results(keys);
    results(end+1,:) = check('results() carries the grouping and the study QC column', ...
        ismember("Group_Treatment", string(Tr.Properties.VariableNames)) && ismember("ParameterDiffers", string(Tr.Properties.VariableNames)) ...
        && ~any(Tr.ParameterDiffers));

    n = S.recomputeAll();
    results(end+1,:) = check('recomputeAll covers the visible sessions', n == 11);

    sess1 = S.session(keys(1));
    results(end+1,:) = check('session(key) is the same handle the second time', sess1 == S.session(keys(1)));

    before = ev('ResultsChanged');
    S.rescan();
    S.results(keys([1 2 4 5]));      % visible keys: recomputeAll left the hidden one out
    results(end+1,:) = check('a rescan of unchanged files keeps the memo', ...
        ev('CatalogChanged') == 1 && ev('ResultsChanged') == before);

    ok = S.save();
    results(end+1,:) = check('save writes the project into the alternate store, not the root', ...
        ok && isfile(fullfile(store, 'project.json')) && ~isfolder(fullfile(root, 'EPsych_Analysis')));
    S2 = behavior.Study(root, Store = store, Roster = "none", CacheFolder = cache);
    results(end+1,:) = check('a new Study on the same root reads the decisions back', ...
        isequal(S2.Selection, keys(1:4)) && S2.isHidden(keys(3)) && S2.windowFor(keys(1)) == "3-83" ...
        && S2.Settings.Window == "20+");
    delete(L);
catch ME
    results(end+1,:) = check(['group 4: ' ME.message], false);
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
fprintf('smoke_test_behavior_study: %d checks, %d failed\n', size(results, 1), nFail);
if nFail > 0
    error('smoke_test_behavior_study:Failed', '%d check(s) failed', nFail);
end
end



function row = check(label, tf)
row = {char(label), logical(tf)};
end

function tf = throwsWith(fcn, id)
tf = false;
try
    fcn();
catch ME
    tf = strcmp(ME.identifier, id);
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

function m = localBump(m, name)
% The Map is a handle, so the caller's copy sees the change; it is returned
% only so the Code Analyzer does not read the assignment as unused.
m(name) = m(name) + 1;
end

function localCleanup(root, cache)
store = strrep(root, 'smoke_', 'store_');
for f = {root, cache, store}
    try
        if isfolder(f{1}), rmdir(f{1}, 's'); end
    catch
    end
end
end
