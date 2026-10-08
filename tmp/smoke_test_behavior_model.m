function smoke_test_behavior_model()
% smoke_test_behavior_model()
% Headless smoke tests for the behavior.* model behind epsych.BehaviorAnalysis
% -- no hardware, no session, no figure.
%
% Builds a synthetic data root (localMakeRoot) holding every shape a lab's
% data tree accumulates: two projects plus a subject folder directly under the
% root, subjects with underscores and digits in their names, sessions tagged
% Pre/Post x Passive/Active, a collision copy, a legacy date-named file, a
% name that disagrees with its folder, a name with no stamp at all, an
% analysis .mat, a hidden folder and an analysis store that must never be
% listed, a zero-trial placeholder, a corrupt file, and a Preview (isTest)
% session. Trial data come from a simulated 1-up/1-down observer on a Depth
% parameter, with catch (TrialType 1) and reminder (TrialType 2) trials.
%
% Groups (later milestones append to this file; keep the numbering):
%   1   behavior.Catalog.parseName; 1b psychophysics.TrialWindow.toText
%   2   behavior.Catalog.scan (and epsych.SessionFiles.summarize Extra=)
%   3   the scan cache, and that a scan writes nothing under the root
%   4   behavior.Settings (JSON round trip, hash, problems, partial structs)
%   5   behavior.Facet (values, order, toText/fromText, available)
%   6   behavior.Session (load, exclusionMask, staircase, fit, analyze, QC)
%   7   behavior.Project (project.json: open writes nothing, mutators, save,
%       merge of two writers, history, alternate store, read-only files)
%   9   behavior.ScriptWriter (session and compare scripts: sections, no
%       GUI or preference calls, settings parse back, write, the scripts run
%       and replicate, a tampered hash fails, a manual grouping travels,
%       figures when behavior.Plot exists)
%   10  behavior.Export (tables built from the schema, CSV/XLSX/MAT, the
%       column dictionary, TSV, empty input)
%   11  roster enrichment (applyRoster)
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_behavior_model.m')"
%
% See also: behavior.Catalog, behavior.hex8, epsych.SessionFiles.summarize,
%   behavior.Settings, behavior.Facet, behavior.Session, behavior.fit.Builtin,
%   behavior.Project, behavior.ScriptWriter, behavior.Export,
%   C:\Users\dstolz\.claude\plans\plan-a-new-tool-jiggly-treasure.md

here = fileparts(mfilename('fullpath'));
if exist('behavior.Catalog', 'class') ~= 8 || exist('epsych.SessionFiles', 'class') ~= 8
    run(fullfile(here, '..', 'epsych_startup.m'));
end

fprintf('\n=== behavior model Smoke Test ===\n\n');
results = {};

% --- Preferences and temporary folders ------------------------------------
savedRoster = localSavePref('ep_RunExpt_Subjects', 'RosterFile');
restorePrefs = onCleanup(@() localRestorePref(savedRoster));

base = fullfile(tempdir, sprintf('epsych_behavior_model_smoke_%d', feature('getpid')));
if isfolder(base), rmdir(base, 's'); end
mkdir(base);
removeBase = onCleanup(@() localRemoveDir(base));

cacheDir = fullfile(base, 'cache');
[root, manifest] = localMakeRoot(fullfile(base, 'data'));
listed = manifest([manifest.Listed]);
sessionsExpected = listed([listed.IsSession]);

c = [];

%% 1. parseName
try
    p = behavior.Catalog.parseName("Rat_7_B_261007T114223_A_Post_Noise.mat");
    results(end+1,:) = check('An underscored subject survives the lazy prefix', ...
        p.NameSubject == "Rat_7_B" && p.Parsed && p.Format == "stamp");
    results(end+1,:) = check('The collision letter is taken off the tags', ...
        p.Collision == "A" && isequal(p.Tags, ["Post" "Noise"]));
    results(end+1,:) = check('Start is the stamp, to the second', ...
        p.Start == datetime(2026,10,7,11,42,23) && p.Precision == "second");

    p = behavior.Catalog.parseName("SUBJ-ID-1234_261007T114223_PrePassive");
    results(end+1,:) = check('Tags without a collision letter, no extension', ...
        p.NameSubject == "SUBJ-ID-1234" && p.Collision == "" && isequal(p.Tags, "PrePassive"));

    p = behavior.Catalog.parseName("X_261007T114223_Post_A_B");
    results(end+1,:) = check('A single letter AFTER the first tag is a tag', ...
        p.Collision == "" && isequal(p.Tags, ["Post" "A" "B"]));

    p = behavior.Catalog.parseName("X_261007T114223_A_B_Post");
    results(end+1,:) = check('Only the first single letter is the collision', ...
        p.Collision == "A" && isequal(p.Tags, ["B" "Post"]));

    p = behavior.Catalog.parseName("X_261007T114223");
    results(end+1,:) = check('A bare stamp has no tags', ...
        p.Parsed && isempty(p.Tags) && p.Collision == "");

    p = behavior.Catalog.parseName("A_261007T114223_261008T090000_Post");
    results(end+1,:) = check('The FIRST stamp wins; a later one is a tag', ...
        p.NameSubject == "A" && p.Start == datetime(2026,10,7,11,42,23) ...
        && isequal(p.Tags, ["261008T090000" "Post"]));

    p = behavior.Catalog.parseName("SUBJ-ID-1234_05-Aug-2026.mat");
    results(end+1,:) = check('A legacy date name is parsed to the day', ...
        p.Parsed && p.Format == "legacy" && p.NameSubject == "SUBJ-ID-1234" ...
        && p.Start == datetime(2026,8,5) && p.Precision == "day" && isempty(p.Tags));

    p = behavior.Catalog.parseName("M01_05-Aug-2026_Pre");
    results(end+1,:) = check('A legacy name keeps its tags', isequal(p.Tags, "Pre"));

    p = behavior.Catalog.parseName("M01_session3.mat");
    results(end+1,:) = check('A name with no stamp is not parsed', ...
        ~p.Parsed && p.NameSubject == "" && isnat(p.Start) && isempty(p.Tags));

    p = behavior.Catalog.parseName("M01_991399T999999_Post");
    results(end+1,:) = check('Digits that are not a valid time are not a stamp', ~p.Parsed);

    results(end+1,:) = check('hex8 is FNV-1a 32 (known vectors)', ...
        behavior.hex8("") == "811c9dc5" && behavior.hex8("a") == "e40c292c" ...
        && behavior.hex8("foobar") == "bf9cf968");

    results(end+1,:) = check('keyFor is relative with "/"', ...
        behavior.Catalog.keyFor(root, fullfile(root, 'ProjA', 'M', 'f.mat')) == "ProjA/M/f.mat");
    results(end+1,:) = check('keyEquals unifies separators (and case on Windows)', ...
        behavior.Catalog.keyEquals("ProjA/M/f.mat", "ProjA\M\f.mat") ...
        && behavior.Catalog.keyEquals("proja/m/F.MAT", "ProjA/M/f.mat") == ispc);
    results(end+1,:) = check('keyFor refuses a file outside the root', ...
        throwsWith(@() behavior.Catalog.keyFor(root, fullfile(base, 'x.mat')), ...
        'behavior:Catalog:NotUnderRoot'));
catch ME
    results(end+1,:) = check(['parseName: ' ME.message], false);
end

%% 1b. TrialWindow.toText round-trips through parse
try
    texts = ["all" "last 20" "first 10" "20-100" "20+"];
    same = true;
    for t = texts
        w = psychophysics.TrialWindow.parse(t);
        same = same && w.toText() == t && isequal(psychophysics.TrialWindow.parse(w.toText()), w);
    end
    results(end+1,:) = check('toText reproduces the shorthand parse reads', same);

    w = psychophysics.TrialWindow.range(3, Inf);
    results(end+1,:) = check('An open range is "A+"', w.toText() == "3+");
    w = psychophysics.TrialWindow.parse("20:end");
    results(end+1,:) = check('"20:end" round-trips as "20+"', ...
        w.toText() == "20+" && isequal(psychophysics.TrialWindow.parse(w.toText()), w));
catch ME
    results(end+1,:) = check(['TrialWindow.toText: ' ME.message], false);
end

%% 2. scan
try
    c = behavior.Catalog(root, CacheFolder = cacheDir);
    ok = c.scan();
    S = c.Sessions;

    results(end+1,:) = check('scan completes', ok && ~isnat(c.ScannedAt));
    results(end+1,:) = check('One row per listed session file', height(S) == numel(sessionsExpected));
    results(end+1,:) = check('Files lists every listed .mat, session or not', ...
        height(c.Files) == numel(listed) && sum(~c.Files.IsSession) == sum(~[listed.IsSession]));

    found = true; placed = true;
    for m = sessionsExpected
        k = find(behavior.Catalog.keyEquals(S.Key, m.Key));
        found = found && isscalar(k);
        if isscalar(k)
            placed = placed && S.Project(k) == m.Project && S.Subject(k) == m.Subject ...
                && isequal(S.Tags{k}, m.Tags) && S.Collision(k) == m.Collision;
        end
    end
    results(end+1,:) = check('Every expected session is keyed by its relative path', found);
    results(end+1,:) = check('Project, subject, tags and collision as the tree and name say', placed);

    k = find(S.Subject == "M01" & S.ProjectPath == "");
    results(end+1,:) = check('A subject folder directly under root takes the root''s name as project', ...
        isscalar(k) && S.Project(k) == "LabRoot");
    k = find(S.Subject == "SUBJ-ID-1234", 1);
    results(end+1,:) = check('ProjectPath is the path above the subject folder', ...
        S.ProjectPath(k) == "ProjA");

    results(end+1,:) = check('Hidden folders and the analysis store are never listed', ...
        ~any(contains(c.Files.Key, ".hidden")) && ~any(contains(c.Files.Key, "EPsych_Analysis")));
    results(end+1,:) = check('The analysis .mat is a file, not a session', ...
        any(endsWith(c.Files.Key, "analysis.mat") & ~c.Files.IsSession) ...
        && ~any(endsWith(S.Key, "analysis.mat")));

    corrupt = manifest(strcmp({manifest.Kind}, 'corrupt')).Key;
    placeholder = manifest(strcmp({manifest.Kind}, 'placeholder')).Key;
    results(end+1,:) = check('The corrupt file is warned about, not dropped', ...
        any(contains(c.Warnings, corrupt)) && localHas(S, corrupt, "unreadable"));
    results(end+1,:) = check('The zero-trial placeholder is warned about and flagged', ...
        any(contains(c.Warnings, placeholder)) && localHas(S, placeholder, "no_trials"));
    results(end+1,:) = check('The Preview session is flagged test_mode', ...
        localHas(S, manifest(strcmp({manifest.Kind}, 'test')).Key, "test_mode"));
    results(end+1,:) = check('A name that disagrees with its folder is flagged name_mismatch', ...
        localHas(S, manifest(strcmp({manifest.Kind}, 'mismatch')).Key, "name_mismatch"));
    results(end+1,:) = check('A name with no stamp is flagged unparsed_name', ...
        localHas(S, manifest(strcmp({manifest.Kind}, 'nostamp')).Key, "unparsed_name"));
    sim = manifest(strcmp({manifest.Kind}, 'sim'));
    results(end+1,:) = check('An ordinary session carries no file flags', ...
        isempty(S.QCFile{behavior.Catalog.keyEquals(S.Key, sim(1).Key)}));

    % Order: projects naturally, then subjects naturally, then start.
    order = S.Project + "|" + S.Subject;
    [~, firstAt] = unique(order, 'stable');
    seen = order(sort(firstAt));
    results(end+1,:) = check('Projects then subjects in NATURAL order (959 before 1234)', ...
        isequal(seen, ["LabRoot|M01"; "ProjA|Rat_7_B"; "ProjA|SUBJ-ID-959"; ...
                       "ProjA|SUBJ-ID-1234"; "ProjB|M01"]));
    sortedStarts = true;
    for g = reshape(seen, 1, [])
        t = S.Start(order == g);
        sortedStarts = sortedStarts && issorted(t, 'MissingPlacement', 'last');
    end
    results(end+1,:) = check('Sessions run by start within a subject', sortedStarts);

    legacy = manifest(strcmp({manifest.Kind}, 'legacy')).Key;
    k = find(behavior.Catalog.keyEquals(S.Key, legacy));
    results(end+1,:) = check('A legacy file starts on its named day', ...
        S.Start(k) == datetime(2026,8,5) && S.Date(k) == datetime(2026,8,5) && S.NameOK(k));
    m = manifest(strcmp({manifest.Kind}, 'nostamp'));
    k = find(behavior.Catalog.keyEquals(S.Key, m.Key));
    results(end+1,:) = check('A name with no stamp starts at its snapshot''s start', ...
        S.Start(k) == m.Start && ~S.NameOK(k));

    % What the one load read from inside the file.
    k = find(behavior.Catalog.keyEquals(S.Key, sim(1).Key));
    C = S.Candidates{k};
    P = S.ParameterMeta{k};
    results(end+1,:) = check('Depth is the first candidate and a snapshot parameter', ...
        ~isempty(C) && C.Field(1) == "Depth" && C.IsParameter(1));
    results(end+1,:) = check('Bookkeeping fields are not candidates', ...
        ~any(ismember(C.Field, ["TrialIndex" "TrialID" "RespCode" "TrialType" "isTest"])));
    d = P(P.Field == "Depth", :);
    results(end+1,:) = check('ParameterMeta carries Depth''s unit and range', ...
        height(d) == 1 && d.Unit == "dB" && d.Min == 0 && d.Max == 60 && d.Type == "Float");
    iti = P(P.Field == "ITI", :);
    results(end+1,:) = check('An "Inf" bound saved as text reads back as Inf', ...
        height(iti) == 1 && isinf(iti.Max));
    results(end+1,:) = check('Sex and species come from the snapshot''s subject', ...
        S.SubjectSex(k) == sim(1).Sex && S.SubjectSpecies(k) == sim(1).Species);
    o = S.Outcome(k);
    results(end+1,:) = check('Outcome counts decode RespCode', ...
        o.Hit > 0 && o.Miss > 0 && o.CorrectReject > 0 ...
        && o.Hit + o.Miss + o.CorrectReject + o.FalseAlarm == S.Trials(k));
    tt = S.TrialTypes{k};
    results(end+1,:) = check('Stimulus, catch and reminder trial types are counted', ...
        isequal(tt.TrialType', [0 1 2]) && sum(tt.Count) == S.Trials(k));
    results(end+1,:) = check('Fields lists the record fields', ...
        all(ismember(["Depth" "RespCode" "TrialType"], S.Fields{k})));
    kt = find(behavior.Catalog.keyEquals(S.Key, manifest(strcmp({manifest.Kind}, 'test')).Key));
    results(end+1,:) = check('NumTest counts isTest records', ...
        S.NumTest(kt) == S.Trials(kt) && S.IsTest(kt) && S.NumTest(k) == 0);

    % Subjects, keys and lookups.
    U = c.Subjects;
    u = U(U.Project == "ProjA" & U.Subject == "SUBJ-ID-1234", :);
    results(end+1,:) = check('Subjects: one row per (project, subject) with counts and dates', ...
        height(U) == 5 && height(u) == 1 && u.NumSessions == 5 ...
        && u.FirstSession == datetime(2026,8,5) && u.Sex == "Female");
    results(end+1,:) = check('A subject in two projects is two Subjects rows', ...
        sum(U.Subject == "M01") == 2);

    keys = c.keysFor(Subject = "SUBJ-ID-1234", Tag = "Post", Position = 1);
    results(end+1,:) = check('keysFor filters by subject and tag position', ...
        numel(keys) == 2 && all(contains(keys, "_Post_")));
    keys = c.keysFor(Project = "ProjB", Tag = "Active");
    results(end+1,:) = check('keysFor filters by project and tag anywhere', ...
        isscalar(keys) && contains(keys, "M1_261013T090000"));
    row = c.session(sim(1).Key);
    results(end+1,:) = check('session(key) returns that row', ...
        height(row) == 1 && behavior.Catalog.keyEquals(row.Key, sim(1).Key));
    results(end+1,:) = check('session(key) refuses an unknown key', ...
        throwsWith(@() c.session("nope.mat"), 'behavior:Catalog:UnknownSession'));

    % Cancel leaves every property as it was.
    before = c.Sessions;
    reads = c.LastScanReads;
    scanned = c.ScannedAt;
    ok = c.scan(Progress = @(k, n) k < 4, UseCache = false);
    results(end+1,:) = check('A cancelled scan returns false and changes nothing', ...
        ~ok && isequal(c.Sessions.Key, before.Key) && c.LastScanReads == reads ...
        && c.ScannedAt == scanned);

    % summarize's Extra callback: a throw is reported, never dropped.
    f = fullfile(root, char(sim(1).Key));
    s = epsych.SessionFiles.summarize(f, Extra = @localBoom);
    results(end+1,:) = check('summarize: a throwing Extra lands in s.Error', ...
        startsWith(s.Error, "Extra: ") && contains(s.Error, "boom") && s.Trials > 0);
    s = epsych.SessionFiles.summarize(f, Extra = @(D, i) struct('N', numel(D), ...
        'Subject', string(i.Subject.Name)));
    results(end+1,:) = check('summarize: Extra sees every trial and the normalized snapshot', ...
        s.Error == "" && s.Extra.N == s.Trials && s.Extra.Subject == sim(1).Subject);
    s = epsych.SessionFiles.summarize(f);
    results(end+1,:) = check('summarize: without Extra, s.Extra is an empty struct', ...
        isstruct(s.Extra) && isempty(fieldnames(s.Extra)));
catch ME
    results(end+1,:) = check(['scan: ' ME.message], false);
end

%% 3. the cache, and a scan that writes nothing under root
try
    cache3 = fullfile(base, 'cache3');
    before = localListing(root);

    c3 = behavior.Catalog(root, CacheFolder = cache3);
    c3.scan();
    results(end+1,:) = check('A first scan reads every file and starts a new cache', ...
        c3.CacheState == "new" && c3.LastScanReads == numel(listed) && isfile(c3.CacheFile));
    results(end+1,:) = check('The cache file is outside the root, named by hex8 of the root', ...
        ~startsWith(c3.CacheFile, string(root), 'IgnoreCase', ispc) ...
        && endsWith(c3.CacheFile, "catalog_" + behavior.hex8(lower(char(c3.Root))) + ".mat"));

    c3b = behavior.Catalog(root, CacheFolder = cache3);
    c3b.scan();
    results(end+1,:) = check('A second scan loads the cache and opens nothing', ...
        c3b.CacheState == "loaded" && c3b.LastScanReads == 0);
    results(end+1,:) = check('A cached scan describes the sessions identically', ...
        isequaln(c3b.Sessions, c3.Sessions));
    results(end+1,:) = check('The same object rescans from the cache too', ...
        c3.scan() && c3.LastScanReads == 0);

    after = localListing(root);
    results(end+1,:) = check('The root is byte-for-byte unchanged (names, bytes, times)', ...
        isequal(before, after));

    c3.scan(UseCache = false);
    results(end+1,:) = check('UseCache=false re-reads every file', c3.LastScanReads == numel(listed));

    % A touched file is read again; nothing else is.
    m = sim(2);
    f = fullfile(root, char(m.Key));
    L = load(f, 'Data', 'Info');
    Data = [L.Data, L.Data(end)];
    Data(end).TrialIndex = numel(Data);
    Info = L.Info;
    save(f, 'Data', 'Info');
    c3.scan();
    k = find(behavior.Catalog.keyEquals(c3.Sessions.Key, m.Key));
    results(end+1,:) = check('A touched file is re-read, and only it', ...
        c3.LastScanReads == 1 && c3.Sessions.Trials(k) == numel(Data));

    % A cache that cannot be used is rebuilt, silently.
    fid = fopen(c3.CacheFile, 'w'); fwrite(fid, 'not a mat file'); fclose(fid);
    c3c = behavior.Catalog(root, CacheFolder = cache3);
    c3c.scan();
    results(end+1,:) = check('An unreadable cache is rebuilt', ...
        startsWith(c3c.CacheState, "rebuilt") && c3c.LastScanReads == numel(listed) ...
        && height(c3c.Sessions) == numel(sessionsExpected));

    inside = fullfile(root, 'cache_inside');
    c3d = behavior.Catalog(root, CacheFolder = inside);
    results(end+1,:) = check('A cache folder inside the root disables the cache', ...
        startsWith(c3d.CacheState, "disabled") && c3d.CacheFile == "");
    c3d.scan();
    results(end+1,:) = check('... and the scan writes nothing there', ...
        startsWith(c3d.CacheState, "disabled") && ~isfolder(inside) ...
        && c3d.LastScanReads == numel(listed));

    c3e = behavior.Catalog(root, CacheFolder = "");
    results(end+1,:) = check('An empty cache folder disables the cache', ...
        startsWith(c3e.CacheState, "disabled") && c3e.scan());

    results(end+1,:) = check('The default cache folder is local application data', ...
        endsWith(behavior.Catalog.defaultCacheFolder(), fullfile('EPsych', 'AnalysisCache')));
catch ME
    results(end+1,:) = check(['cache: ' ME.message], false);
end

%% 4. Settings
try
    s = behavior.Settings();
    st = s.toStruct();
    txt = jsonencode(st);
    [s2, w] = behavior.Settings.fromStruct(jsondecode(txt));
    results(end+1,:) = check('Settings: toStruct -> JSON -> fromStruct gives the same settings', ...
        isequal(s2, s) && isempty(w));
    names = fieldnames(st);
    results(end+1,:) = check('toStruct leads with SettingsVersion = 1', ...
        strcmp(names{1}, 'SettingsVersion') && st.SettingsVersion == 1);

    sx = behavior.Settings(Parameter = "Depth", Window = "20+", ExcludeTrialTypes = [2 3], ...
        Staircase = struct(WeightedStepAfterYes = -2, ThresholdFormula = "GeometricMean"), ...
        Metrics = struct(infCorrection = [0.01 0.99]), Fit = struct(Bootstrap = 50, RandomSeed = []));
    txtx = jsonencode(sx.toStruct());
    [sx2, wx] = behavior.Settings.fromStruct(jsondecode(txtx));
    results(end+1,:) = check('... including vectors jsondecode returns as columns, and []', ...
        isequal(sx2, sx) && isempty(wx) && isequal(sx2.ExcludeTrialTypes, [2 3]) ...
        && isequal(sx2.Metrics.infCorrection, [0.01 0.99]));
    results(end+1,:) = check('No NaN, Inf or null anywhere in the JSON', ...
        ~any(contains([string(txt) string(txtx)], ["NaN" "Inf" "null"])));
    sn = behavior.Settings(Staircase = struct(WeightedStepAfterYes = NaN));
    results(end+1,:) = check('A NaN "find it" step is stored as [] and handed to Staircase as NaN', ...
        isempty(sn.Staircase.WeightedStepAfterYes) && isnan(sn.staircaseProperties().WeightedStepAfterYes));

    h = s.hash();
    results(end+1,:) = check('hash is eight hex digits', ~isempty(regexp(h, '^[0-9a-f]{8}$', 'once')));
    results(end+1,:) = check('hash is the same in any field order', ...
        behavior.Settings.fromStruct(localReverseFields(st)).hash() == h ...
        && behavior.Settings.fromStruct(localReverseFields(sx.toStruct())).hash() == sx.hash());
    results(end+1,:) = check('QC and Compare edits leave the hash alone', ...
        behavior.Settings(QC = struct(MinTrials = 5), Compare = struct(BootstrapCI = true)).hash() == h);
    results(end+1,:) = check('A Window edit changes the hash', behavior.Settings(Window = "20+").hash() ~= h);

    results(end+1,:) = check('problems() is empty for the defaults', isempty(s.problems()));
    p = behavior.Settings(Window = "banana").problems();
    results(end+1,:) = check('problems() reports an unreadable Window', ...
        isscalar(p) && startsWith(p, "Window:"));
    % psignifit itself is tmp/smoke_test_behavior_psignifit.m's; here only
    % that a missing install is reported (override makes it missing anywhere).
    behavior.fit.Psignifit.override("missing");
    p = behavior.Settings(Fit = struct(Engine = "psignifit")).problems();
    behavior.fit.Psignifit.override("");
    results(end+1,:) = check('problems() reports a missing psignifit', ...
        isscalar(p) && startsWith(p, "psignifit: "));
    p = behavior.Settings(Analysis = "Detection").problems();
    results(end+1,:) = check('problems() reports an analysis this version lacks', ...
        isscalar(p) && contains(p, "not available in this version"));
    p = behavior.Settings(Fit = struct(CriterionScale = "absolute", ThresholdCriterion = 0.3, GuessRate = 0.5)).problems();
    results(end+1,:) = check('problems() reports an absolute criterion below the guess rate', ...
        isscalar(p) && contains(p, "asymptotes"));

    t = behavior.Settings(Fit = struct(Shape = "weibull"));
    results(end+1,:) = check('A partial sub-struct keeps the other defaults (and the canonical spelling)', ...
        t.Fit.Shape == "Weibull" && t.Fit.Engine == "builtin" && t.Fit.ConfidenceLevel == 0.95 ...
        && t.Fit.Enabled && isequal(t.Staircase, s.Staircase));
    results(end+1,:) = check('An unknown sub-struct field is an error', ...
        throwsWith(@() behavior.Settings(Fit = struct(Shap = "Weibull")), 'behavior:Settings:UnknownField'));
    results(end+1,:) = check('A bad sub-struct value is an error', ...
        throwsWith(@() behavior.Settings(Fit = struct(Shape = "Cubic")), 'behavior:Settings:InvalidValue'));

    st3 = st;
    st3.Bogus = 1;
    st3.Fit.Shape = "Cubic";
    st3.SettingsVersion = 2;
    [s3, w3] = behavior.Settings.fromStruct(st3);
    results(end+1,:) = check('fromStruct forgives: unknown field, bad value, newer version (3 warnings)', ...
        s3.Fit.Shape == "Logistic" && numel(w3) == 3);

    a = s.staircaseArgs();
    fa = behavior.Settings(Staircase = struct(Direction = "Up")).fitArgs();
    results(end+1,:) = check('staircaseArgs passes trial types as BitMasks; an Up staircase fits decreasing', ...
        a{2} == epsych.BitMask.TrialType_0 && a{4} == epsych.BitMask.TrialType_1 ...
        && fa{find(strcmp(fa(1:2:end), 'Direction')) * 2} == "decreasing");
    results(end+1,:) = check('describe() is one sentence', isStringScalar(s.describe()) && endsWith(s.describe(), "."));
catch ME
    results(end+1,:) = check(['Settings: ' ME.message], false);
end

%% 5. Facet
try
    T = c.Sessions;
    T.Group_Treatment = repmat("", height(T), 1);
    T.Group_Treatment(T.Subject == "SUBJ-ID-1234") = "Noise";
    T.Group_Treatment(T.Subject == "Rat_7_B") = "Control";

    v = behavior.Facet.fromText("tag:1").values(T);
    want = repmat("(none)", height(T), 1);
    for i = 1:height(T)
        if ~isempty(T.Tags{i}), want(i) = T.Tags{i}(1); end
    end
    results(end+1,:) = check('Facet tag:1 is the first tag, "(none)" without one', ...
        isequal(v, want) && any(v == "(none)") && any(v == "Pre") && any(v == "Post"));
    v = behavior.Facet("tag", Index = 3).values(T);
    results(end+1,:) = check('A tag position no session has is "(none)" everywhere', all(v == "(none)"));
    results(end+1,:) = check('Facet project is the Project column', ...
        isequal(behavior.Facet("project").values(T), T.Project));
    v = behavior.Facet.fromText("month").values(T);
    results(end+1,:) = check('Facet month is yyyy-MM', isequal(v, string(T.Start, 'yyyy-MM')));
    v = behavior.Facet.fromText("week").values(T);
    results(end+1,:) = check('Facet week is yyyy-''W''ww', all(~cellfun(@isempty, regexp(v, '^\d{4}-W\d{2}$', 'once'))));
    W = table(datetime([2026 12 31; 2027 1 1; 2027 1 4; NaN NaN NaN]), ["a"; "a"; "a"; "a"], ...
        'VariableNames', {'Start', 'Subject'});
    results(end+1,:) = check('... the ISO week, whose year is its Thursday''s; undated is "(none)"', ...
        isequal(behavior.Facet("week").values(W), ["2026-W53"; "2026-W53"; "2027-W01"; "(none)"]));

    v = behavior.Facet("session").values(T);
    k = T.Subject == "SUBJ-ID-1234";
    starts = T.Start(k);
    [~, ord] = sort(starts);
    rank = zeros(numel(starts), 1);
    rank(ord) = 1:numel(starts);
    results(end+1,:) = check('Facet session is each subject''s ordinal by start', ...
        isequal(v(k), string(rank)) && v(find(k & T.Start == datetime(2026,8,5), 1)) == "1");
    m01 = T.Subject == "M01";
    results(end+1,:) = check('... counted across projects for one subject', ...
        isequal(sort(double(v(m01))), (1:sum(m01))'));

    v = behavior.Facet.fromText("manual:Treatment").values(T);
    results(end+1,:) = check('Facet manual:Treatment reads Group_Treatment, "(none)" when unassigned', ...
        all(v(T.Subject == "SUBJ-ID-1234") == "Noise") && all(v(T.Subject == "Rat_7_B") == "Control") ...
        && all(v(T.Subject == "M01") == "(none)"));
    v = behavior.Facet.fromText("manual:Diet").values(T);
    results(end+1,:) = check('A grouping with no column is "(none)" everywhere', all(v == "(none)"));

    f1 = behavior.Facet.fromText("tag:1");
    [lv, idx] = f1.order(T);
    results(end+1,:) = check('order: tag levels in the order their phases happened, "(none)" last, idx maps rows', ...
        isequal(lv, ["Pre"; "Post"; "(none)"]) && isequal(lv(idx), f1.values(T)));

    F = behavior.Facet.available(T, "Treatment");
    same = true;
    for f = F
        same = same && isequal(behavior.Facet.fromText(f.toText()), f) && f.label() ~= "";
    end
    kinds = [F.Kind];
    results(end+1,:) = check('toText/fromText round-trips every available facet', same ...
        && all(ismember(setdiff(behavior.Facet.Kinds, ["tag" "manual"]), kinds)));
    results(end+1,:) = check('available lists tag positions up to the most tags any session has', ...
        sum(kinds == "tag") == max(T.NumTags) && max(T.NumTags) == 2 ...
        && isscalar(F(kinds == "manual")) && F(kinds == "manual").Name == "Treatment");
    results(end+1,:) = check('Text that names no facet reads as "none"', ...
        behavior.Facet.fromText("banana").Kind == "none" && behavior.Facet.fromText("tag:x").Kind == "none");
    results(end+1,:) = check('A tag facet without a position is an error', ...
        throwsWith(@() behavior.Facet("tag"), 'behavior:Facet:InvalidIndex'));
catch ME
    results(end+1,:) = check(['Facet: ' ME.message], false);
end

%% 6. Session.analyze
try
    s = behavior.Settings();
    sims = manifest(strcmp({manifest.Kind}, 'sim'));

    % The simulated observer: 50% point mu = 20 dB, step 2 dB (localSimData).
    MU = 20;
    STEP = 2;
    thr = nan(1, numel(sims));
    fitThr = nan(1, numel(sims));
    for i = 1:numel(sims)
        Ri = behavior.Session.load(c.session(sims(i).Key)).analyze(s);
        thr(i) = Ri.Threshold;
        fitThr(i) = Ri.Fit.Threshold;
    end
    results(end+1,:) = check(sprintf('Reversal thresholds sit within one step of mu (median %.2f, range %.1f-%.1f)', ...
        median(thr), min(thr), max(thr)), abs(median(thr) - MU) <= STEP && all(isfinite(thr)));
    results(end+1,:) = check(sprintf('Fitted thresholds too (median %.2f)', median(fitThr, 'omitnan')), ...
        abs(median(fitThr, 'omitnan') - MU) <= STEP);

    row = c.session(sims(1).Key);
    sess = behavior.Session.load(row);
    R = sess.analyze(s);
    results(end+1,:) = check('analyze picks Depth automatically, with its unit', ...
        R.Parameter == "Depth" && R.ParameterAuto && R.Unit == "dB" && R.SettingsHash == s.hash());
    results(end+1,:) = check('A normal session analyses cleanly: no messages, no QC flags', ...
        isempty(R.Messages) && isempty(R.QC) && R.NumIncluded == row.Trials);
    results(end+1,:) = check('Fit converges on a normal session, in the common schema', ...
        R.Fit.Engine == "builtin" && R.Fit.Converged && R.Fit.Identifiable && isfinite(R.Fit.Threshold) ...
        && isequal(fieldnames(R.Fit)', {'Engine','Shape','Threshold','Alpha','Beta','Gamma','Lambda', ...
        'Width','Eta','Deviance','Warnings', ...
        'Levels','NumYes','NumTotal','Proportion','Curve','CI','Converged','Identifiable','Message','Raw'}));

    R20 = sess.analyze(behavior.Settings(Window = "20+"));
    Rw = sess.analyze(s, Window = "20+");
    results(end+1,:) = check('Window "20+" includes 19 fewer trials', ...
        R.NumIncluded - R20.NumIncluded == 19 && R20.Window == "20+" && all(R20.Excluded(1:19)));
    results(end+1,:) = check('... and a per-session Window override does the same', ...
        Rw.NumIncluded == R20.NumIncluded && Rw.SettingsHash == s.hash() && isequaln(Rw.Threshold, R20.Threshold));

    tt = [sess.Data.TrialType];
    nRem = sum(tt == 2);
    Rx = sess.analyze(behavior.Settings(ExcludeTrialTypes = 2));
    results(end+1,:) = check('ExcludeTrialTypes = 2 removes every reminder trial', ...
        nRem > 0 && Rx.NumIncluded == R.NumIncluded - nRem && ~any(tt(~Rx.Excluded) == 2));

    nStim = sum(tt == 0 & ~R.Excluded);
    d = [sess.Data.Depth];
    results(end+1,:) = check('Track has one entry per included stimulus trial', ...
        numel(R.Track.TrialIndex) == nStim && R.NumStimulus == nStim ...
        && isequal(R.Track.Value, d(R.Track.TrialIndex)) && sum(R.Track.Reversal) == R.ReversalCount ...
        && isequal(R.ReversalValues, d(R.ReversalIdx)));

    N = R.Metrics.N;
    o = row.Outcome;
    results(end+1,:) = check('Metrics.N agrees with the catalog''s Outcome counts', ...
        N.Total == row.Trials && N.FalseAlarm == o.FalseAlarm && N.CorrectReject == o.CorrectReject ...
        && N.Hit + N.Miss + nRem == o.Hit + o.Miss && N.Catch == sum(tt == 1) && R.NumCatch == N.Catch);
    results(end+1,:) = check('MetricsSummary is SessionMetrics.summary()', ...
        istable(R.MetricsSummary) && height(R.MetricsSummary) > 0 && ismember("DPrime", R.MetricsSummary.Name));

    Rm = sess.analyze(behavior.Settings(Parameter = "Nope"));
    results(end+1,:) = check('A parameter the file lacks: NaN, no_parameter, a message', ...
        isnan(Rm.Threshold) && any(Rm.QC == "no_parameter") && any(contains(Rm.Messages, "Nope")) ...
        && Rm.Metrics.N.Total == row.Trials);

    test = manifest(strcmp({manifest.Kind}, 'test'));
    st = behavior.Session.load(c.session(test.Key));
    Rt = st.analyze(s);
    results(end+1,:) = check('ExcludeTest leaves the Preview session with nothing included, and says so', ...
        Rt.NumIncluded == 0 && isnan(Rt.Threshold) && any(contains(Rt.Messages, "test trials")) ...
        && any(Rt.QC == "test_mode") && any(Rt.QC == "low_trials"));
    Rt2 = st.analyze(behavior.Settings(ExcludeTest = false));
    results(end+1,:) = check('... and ExcludeTest = false analyses it', ...
        Rt2.NumIncluded == numel(st.Data) && isfinite(Rt2.Threshold));

    corrupt = manifest(strcmp({manifest.Kind}, 'corrupt'));
    sc = behavior.Session.load(c.session(corrupt.Key));
    Rc = sc.analyze(s);
    results(end+1,:) = check('analyze on the corrupt file: no throw, NaN, a message, unreadable', ...
        sc.Error ~= "" && isnan(Rc.Threshold) && ~isempty(Rc.Messages) && any(Rc.QC == "unreadable"));

    legacy = manifest(strcmp({manifest.Kind}, 'legacy'));
    Rl = behavior.Session.load(c.session(legacy.Key)).analyze(s);
    results(end+1,:) = check('A legacy file with no snapshot still analyses (no unit)', ...
        Rl.Parameter == "Depth" && Rl.Unit == "" && isfinite(Rl.Threshold));

    behavior.fit.Psignifit.override("missing");
    Rp = sess.analyze(behavior.Settings(Fit = struct(Engine = "psignifit")));
    behavior.fit.Psignifit.override("");
    results(end+1,:) = check('A missing psignifit does not throw: fit_failed and the reason', ...
        Rp.Fit.Engine == "psignifit" && any(Rp.QC == "fit_failed") && any(contains(Rp.Messages, "psignifit")) ...
        && ~isempty(Rp.Fit.Levels) && Rp.Threshold == R.Threshold);
    Rq = sess.analyze(behavior.Settings(QC = struct(MinTrials = 1000, MinReversals = 1000, MaxAbortRate = 0)));
    results(end+1,:) = check('QC thresholds raise low_trials and few_reversals', ...
        all(ismember(["low_trials" "few_reversals"], Rq.QC)) && ~any(Rq.QC == "high_abort_rate"));

    sb = behavior.Session.load(fullfile(root, char(sims(1).Key)), Root = root);
    results(end+1,:) = check('load from a bare path equals load from the row (Key/Subject/Tags/...)', ...
        sb.Key == sess.Key && sb.Subject == sess.Subject && isequal(sb.Tags, sess.Tags) ...
        && sb.Project == sess.Project && sb.ProjectPath == sess.ProjectPath && sb.Start == sess.Start ...
        && isequal(sb.ParameterMeta, sess.ParameterMeta) && isequal(sb.Candidates, sess.Candidates) ...
        && isequal(sb.QCFile, sess.QCFile) && isequal(sb.Data, sess.Data) && sess.Root == string(root));
    sm = behavior.Session.load(fullfile(root, char(manifest(strcmp({manifest.Kind}, 'mismatch')).Key)), Root = root);
    results(end+1,:) = check('... including its file-level QC flags', any(sm.QCFile == "name_mismatch"));

    S1 = sess.staircase(behavior.Settings(Staircase = struct(ThresholdFromLastNReversals = 4)));
    results(end+1,:) = check('staircase() is configured by the settings and labelled from the session', ...
        isa(S1, 'psychophysics.Staircase') && S1.ThresholdFromLastNReversals == 4 ...
        && S1.Subject == sess.Subject && S1.Unit == "dB" && isequal(S1.BoxID, 1));
    results(end+1,:) = check('staircase() refuses a parameter the file lacks', ...
        throwsWith(@() sess.staircase(behavior.Settings(Parameter = "Nope")), 'behavior:Session:MissingParameter'));

    [ex, info] = behavior.Session.exclusionMask(sess.Data, Window = "last 10", ExcludeTrialTypes = 1);
    results(end+1,:) = check('exclusionMask reports what it did', ...
        info.NumTrials == numel(sess.Data) && info.NumInWindow == 10 && info.Window == "last 10" ...
        && info.NumIncluded == sum(~ex) && all(ex(1:end-10)) ...
        && isequal(info.NumByType.TrialType', unique(tt(end-9:end))));
    results(end+1,:) = check('exclusionMask refuses a window it cannot read', ...
        throwsWith(@() behavior.Session.exclusionMask(sess.Data, Window = "banana"), ...
        'psychophysics:TrialWindow:InvalidSpec'));
    results(end+1,:) = check('candidates is the catalog''s rule (Depth first)', ...
        isequal(behavior.Session.candidates(sess.Data, sess.ParameterMeta), row.Candidates{1}));
catch ME
    results(end+1,:) = check(['Session: ' ME.message ' (' ME.stack(1).name ':' num2str(ME.stack(1).line) ')'], false);
end

%% 7. Project (project.json)
% Every write happens on a COPY of the root (its stray store folder removed),
% so the root later groups scan is exactly as the fixture built it.
try
    pr = fullfile(base, 'proj7', 'LabRoot');
    mkdir(fileparts(pr));
    copyfile(root, pr);
    store = fullfile(pr, char(behavior.Catalog.StoreFolder));
    if isfolder(store), rmdir(store, 's'); end
    pfile = fullfile(store, 'project.json');

    kS = c.keysFor(Subject = "SUBJ-ID-1234");
    kR = c.keysFor(Subject = "Rat_7_B");
    [kA, kB, kC, kD, kE] = deal(kS(1), kS(2), kS(3), kS(4), kR(1));

    before = localListing(pr);
    P = behavior.Project.open(pr);
    results(end+1,:) = check('open writes nothing under the root (no folder, no file)', ...
        isequal(before, localListing(pr)) && ~isfolder(store));
    results(end+1,:) = check('A new project is clean, writable and holds the default settings', ...
        ~P.Dirty && ~P.ReadOnly && isempty(P.Warnings) && P.Revision == 0 ...
        && isequal(P.Settings.toStruct(), behavior.Settings().toStruct()) ...
        && height(P.Sessions) == 0 && isempty(P.Groupings) && isempty(P.Selection.Keys) ...
        && P.File == string(pfile));

    % Every mutator marks a fresh project Dirty.
    edits = {
        'hide',         @(Q) Q.hide(kA, true, Reason = "lid open")
        'setWindow',    @(Q) Q.setWindow(kA, "20+")
        'setComment',   @(Q) Q.setComment("SUBJ-ID-1234", "left ear")
        'setSettings',  @(Q) Q.setSettings(behavior.Settings(Window = "last 50"))
        'savePreset',   @(Q) Q.savePreset("Twelve")
        'addGrouping',  @(Q) Q.addGrouping("Treatment", ["Control" "Noise"])
        'setFacets',    @(Q) Q.setFacets(GroupBy = "tag:1")
        'setSelection', @(Q) Q.setSelection(kS)
        };
    dirty = false(1, size(edits, 1));
    for i = 1:size(edits, 1)
        Q = behavior.Project.open(pr);
        edits{i, 2}(Q);
        dirty(i) = Q.Dirty;
    end
    results(end+1,:) = check(strjoin(['Each mutator sets Dirty' edits(~dirty, 1)'], ' -- not: '), all(dirty));
    results(end+1,:) = check('Setting what is already there is no edit', ...
        localNoEdit(pr, @(Q) Q.setSettings(behavior.Settings())) ...
        && localNoEdit(pr, @(Q) Q.hide(kA, false)) && localNoEdit(pr, @(Q) Q.setWindow(kA, "")));

    P.hide(kA, true, Reason = "lid open");
    P.setWindow(kA, "20:end");
    P.setComment(kC, "odd session");
    P.setComment("SUBJ-ID-1234", "left ear");
    results(end+1,:) = check('hide, setWindow and setComment take effect (window text canonical)', ...
        P.Dirty && P.isHidden(kA) && ~P.isHidden(kB) && P.windowFor(kA) == "20+" ...
        && P.windowFor(kB) == "" && P.commentFor(kC) == "odd session" ...
        && P.commentFor("SUBJ-ID-1234") == "left ear" && P.commentFor(kA) == "" ...
        && isequal(P.isHidden([kA kB]), [true false]));
    results(end+1,:) = check('setWindow refuses a window it cannot read', ...
        throwsWith(@() P.setWindow(kB, "banana"), 'behavior:Project:InvalidWindow') ...
        && P.windowFor(kB) == "");

    P.addGrouping("Treatment", ["Control" "Noise"]);
    P.assign("Treatment", "SUBJ-ID-1234", "Noise");
    P.assign("Treatment", "Rat_7_B", "Control");
    P.assign("Treatment", kB, "Control");               % one session overrides its subject
    results(end+1,:) = check('assign: a subject level, and a per-session override', ...
        P.groupingLevel("Treatment", kA, "SUBJ-ID-1234") == "Noise" ...
        && P.groupingLevel("Treatment", kB, "SUBJ-ID-1234") == "Control" ...
        && P.groupingLevel("Treatment", "x/M01/y.mat", "M01") == "" ...
        && P.groupingLevel("Nope", kA, "SUBJ-ID-1234") == "");
    results(end+1,:) = check('assign refuses a level the grouping lacks', ...
        throwsWith(@() P.assign("Treatment", "M01", "Placebo"), 'behavior:Project:UnknownLevel'));
    results(end+1,:) = check('addGrouping refuses a name already used', ...
        throwsWith(@() P.addGrouping("Treatment", "A"), 'behavior:Project:GroupingExists'));

    P.setFacets(GroupBy = "tag:1", ColorBy = "manual:Treatment", Kind = "strip");
    results(end+1,:) = check('setFacets keeps facet text and leaves unstated fields alone', ...
        P.Facets.GroupBy == "tag:1" && P.Facets.ColorBy == "manual:Treatment" ...
        && P.Facets.Kind == "strip" && P.Facets.XAxis == "date" && ~isnat(P.Facets.Modified));
    results(end+1,:) = check('setFacets refuses text that names no facet', ...
        throwsWith(@() P.setFacets(GroupBy = "banana"), 'behavior:Project:InvalidFacet') ...
        && P.Facets.GroupBy == "tag:1");

    P.setSelection([kA kB kA]);
    results(end+1,:) = check('setSelection keeps the order and drops duplicates', ...
        isequal(P.Selection.Keys, [kA kB]));

    P.setSettings(behavior.Settings(Window = "20+", ...
        Staircase = struct(ThresholdFromLastNReversals = 8)));
    P.savePreset("Eight", View = struct(GroupBy = "subject"));
    P.setSettings(behavior.Settings());
    P.setFacets(GroupBy = "month");
    s7 = P.applyPreset("Eight");
    results(end+1,:) = check('savePreset/applyPreset restore the settings and the view', ...
        s7.Window == "20+" && P.Settings.Window == "20+" ...
        && P.Settings.Staircase.ThresholdFromLastNReversals == 8 ...
        && P.Facets.GroupBy == "subject" && P.Facets.Kind == "strip");

    % applyGroupings: what Study.sessions and Facet "manual" read.
    G = P.applyGroupings(c.Sessions);
    subj = string(G.Subject);
    want = repmat("(none)", height(G), 1);
    want(subj == "SUBJ-ID-1234") = "Noise";
    want(subj == "Rat_7_B") = "Control";
    want(behavior.Catalog.keyEquals(G.Key, kB)) = "Control";
    isA = behavior.Catalog.keyEquals(G.Key, kA);
    isC = behavior.Catalog.keyEquals(G.Key, kC);
    results(end+1,:) = check('applyGroupings adds Group_Treatment, Hidden, Window, Comment', ...
        all(ismember(["Group_Treatment" "Hidden" "Window" "Comment"], G.Properties.VariableNames)) ...
        && height(G) == height(c.Sessions) && isequal(G.Group_Treatment, want) ...
        && isequal(G.Hidden, isA) && all(G.Window(isA) == "20+") && all(G.Window(~isA) == "") ...
        && all(G.Comment(isC) == "odd session") && all(G.Comment(~isC) == ""));
    results(end+1,:) = check('Facet "manual:Treatment" reads the column applyGroupings wrote', ...
        isequal(behavior.Facet.fromText("manual:Treatment").values(G), want));

    % save
    before = localListing(pr);
    results(end+1,:) = check('save creates the store folder and the file', ...
        P.save() && isfile(pfile) && ~P.Dirty && P.Revision == 1);
    after = localListing(pr);
    added = setdiff(after.Path, before.Path);
    kept = ismember(after.Path, before.Path);
    results(end+1,:) = check('... and nothing else under the root', ...
        isequal(sort(added), sort(string({store; pfile}))) && isequal(after(kept,:), before));
    txt = fileread(pfile);
    results(end+1,:) = check('The JSON holds no NaN, Inf or null', ...
        isempty(regexp(txt, '\<(NaN|Inf|Infinity|null)\>', 'once')));
    results(end+1,:) = check('Records are arrays of objects, keyed by a Key field', ...
        ~isempty(regexp(txt, '"Sessions":\s*\[', 'once')) && contains(txt, """Key"": """ + kA + """") ...
        && ~isempty(regexp(txt, '"Modified":\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}"', 'once')));

    Q = behavior.Project.open(pr);
    results(end+1,:) = check('Reopened, it equals the saved object field for field', ...
        ~Q.Dirty && ~Q.ReadOnly && isempty(Q.Warnings) && Q.Revision == P.Revision ...
        && isequaln(rmfield(Q.toStruct(), 'Revision'), rmfield(P.toStruct(), 'Revision')) ...
        && isequaln(Q.applyGroupings(c.Sessions), G));
    results(end+1,:) = check('A save with nothing to save writes nothing', ...
        localSameFile(pfile, @() Q.save()) && Q.Revision == 1);

    % Two writers, different sessions: both edits survive.
    A = behavior.Project.open(pr);
    B = behavior.Project.open(pr);
    A.setComment(kD, "from A");
    B.setComment(kE, "from B");
    okA = A.save();
    okB = B.save();
    R = behavior.Project.open(pr);
    results(end+1,:) = check('Two writers editing different sessions: both survive (merge)', ...
        okA && okB && R.commentFor(kD) == "from A" && R.commentFor(kE) == "from B" ...
        && R.isHidden(kA) && R.Revision == 3 && B.commentFor(kD) == "from A");

    % The same session edited by both: the later edit wins, whoever saves last.
    A.setComment(kD, "A, earlier");
    pause(0.02);
    B.setComment(kD, "B, later");
    okB = B.save();
    okA = A.save();
    R = behavior.Project.open(pr);
    results(end+1,:) = check('The same session edited by both: the later Modified wins', ...
        okA && okB && R.commentFor(kD) == "B, later" && A.commentFor(kD) == "B, later");

    % A removal is not undone by the other writer's stale copy.
    A = behavior.Project.open(pr);
    B = behavior.Project.open(pr);
    A.hide(kA, false);
    A.setWindow(kA, "");                                % the row is now default, so removed
    A.save();
    B.setComment(kE, "B again");
    B.save();
    R = behavior.Project.open(pr);
    results(end+1,:) = check('An un-hidden session stays un-hidden after a stale writer saves', ...
        ~R.isHidden(kA) && R.windowFor(kA) == "" && R.commentFor(kE) == "B again");

    % A preset deleted in one object and renamed in the other.
    A = behavior.Project.open(pr);
    A.savePreset("P1");
    A.save();
    B = behavior.Project.open(pr);
    A.deletePreset("P1");
    B.renamePreset("P1", "P2");
    okA = A.save();
    okB = B.save();
    R = behavior.Project.open(pr);
    names = string({R.Presets.Name});
    results(end+1,:) = check('A preset deleted in one object and renamed in the other merges by name', ...
        okA && okB && ~ismember("P1", names) && ismember("P2", names) && ismember("Eight", names));

    % History keeps the newest three.
    H = behavior.Project.open(pr);
    for i = 1:5
        H.setComment(kB, "revision " + i);
        H.save();
    end
    hist = dir(fullfile(store, '.history', 'project_*.json'));
    results(end+1,:) = check(sprintf('.history keeps the newest 3 copies after 5 saves (%d)', numel(hist)), ...
        numel(hist) == 3 && ~any(startsWith({dir(store).name}, 'project.json.tmp')));

    % A store path taken by a FILE: refused, and an alternate store works.
    rootF = fullfile(base, 'proj7file', 'LabRoot');
    mkdir(rootF);
    fid = fopen(fullfile(rootF, char(behavior.Catalog.StoreFolder)), 'w'); fwrite(fid, 'x'); fclose(fid);
    beforeF = localListing(rootF);
    F = behavior.Project.open(rootF);
    F.hide("M01/M01_261001T090000.mat", true);
    nWarn = numel(F.Warnings);
    results(end+1,:) = check('A store path that is a file: canWrite false, save false with a warning', ...
        ~F.canWrite() && ~F.save() && numel(F.Warnings) == nWarn + 1 && F.Dirty);
    alt = fullfile(base, 'altstore');
    F2 = behavior.Project.open(rootF, Store = alt);
    F2.hide("M01/M01_261001T090000.mat", true);
    results(end+1,:) = check('An alternate Store under tempdir is written instead', ...
        F2.canWrite() && F2.save() && isfile(fullfile(alt, 'project.json')) ...
        && isequal(localListing(rootF), beforeF) ...
        && behavior.Project.open(rootF, Store = alt).isHidden("M01/M01_261001T090000.mat"));

    % A file from a newer EPsych: read-only, and never written.
    rootV = fullfile(base, 'proj7v', 'LabRoot');
    mkdir(fullfile(rootV, char(behavior.Catalog.StoreFolder)));
    st = jsondecode(fileread(pfile));
    st.FormatVersion = 99;
    st.FutureField = "something new";
    vfile = fullfile(rootV, char(behavior.Catalog.StoreFolder), 'project.json');
    fid = fopen(vfile, 'w'); fwrite(fid, jsonencode(st, PrettyPrint = true)); fclose(fid);
    V = behavior.Project.open(rootV);
    results(end+1,:) = check('A newer FormatVersion opens read-only, with a warning, keeping what it read', ...
        V.ReadOnly && V.FormatVersion == 99 && any(contains(V.Warnings, "newer")) ...
        && V.commentFor(kD) == "B, later" && ismember("P2", string({V.Presets.Name})));
    V.hide(kB, true);
    results(end+1,:) = check('... and save refuses, leaving the file byte-identical', ...
        localSameFile(vfile, @() V.save()) && ~V.save());

    % A file that is not JSON: read-only, default settings.
    rootG = fullfile(base, 'proj7g', 'LabRoot');
    mkdir(fullfile(rootG, char(behavior.Catalog.StoreFolder)));
    gfile = fullfile(rootG, char(behavior.Catalog.StoreFolder), 'project.json');
    fid = fopen(gfile, 'w'); fwrite(fid, '{{{ this is not json'); fclose(fid);
    Gp = behavior.Project.open(rootG);
    results(end+1,:) = check('An unreadable project.json opens read-only with defaults and a warning', ...
        Gp.ReadOnly && ~isempty(Gp.Warnings) && contains(Gp.Warnings(1), "JSON") ...
        && isequal(Gp.Settings.toStruct(), behavior.Settings().toStruct()) ...
        && localSameFile(gfile, @() Gp.save()));

    results(end+1,:) = check('summary is one line naming the file', ...
        isStringScalar(R.summary()) && contains(R.summary(), "project.json") ...
        && ~contains(R.summary(), newline));

    rmdir(fullfile(base, 'proj7'), 's');
catch ME
    results(end+1,:) = check(['Project: ' ME.message ' (' ME.stack(1).name ':' num2str(ME.stack(1).line) ')'], false);
end

%% 9. ScriptWriter
try
    out9 = fullfile(base, 'script9');
    mkdir(out9);
    removeOut9 = onCleanup(@() localRemoveDir(out9));
    St9 = behavior.Study(string(root), Store = string(fullfile(out9, 'store')), Roster = "none", ...
        CacheFolder = string(cacheDir));
    sims9 = manifest(strcmp({manifest.Kind}, 'sim'));
    keys9 = string({sims9([1 3 6]).Key});          % two subjects, Pre and Post
    St9.setWindow(keys9(2), "5-70");                 % one window override travels too

    [codeS, infoS] = behavior.ScriptWriter.session(St9, keys9(1), Figures = false);
    [codeC, infoC] = behavior.ScriptWriter.compare(St9, keys9, GroupBy = "tag:1", ...
        ColorBy = "subject", Figures = false);
    banned = ["gui." "getpref" "setpref" "uialert"];
    results(end+1,:) = check('session script: header, setup, settings, session, tables, export, local functions in order', ...
        startsWith(codeS{1}, '%% Replicate: SUBJ-ID-1234') && localInOrder(codeS, ["%% Setup" "%% Settings" ...
        "%% Session 1 of 1" "%% Tables" "%% Export" "%% Local functions"]) ...
        && ~any(startsWith(codeS, '%% Figures')));
    results(end+1,:) = check('compare script: every session, the statistics and the summary, in order', ...
        localInOrder(codeC, ["%% Setup" "%% Settings" "%% Session 1 of 3" "%% Session 2 of 3" ...
        "%% Session 3 of 3" "%% Tables" "%% Export" "%% Summary" "%% Local functions"]) ...
        && any(startsWith(codeC, 'D = behavior.Stats.describe(T, "Threshold"')) ...
        && any(contains(codeC, 'Window = "5-70"')));
    results(end+1,:) = check('Neither script mentions gui., getpref, setpref or uialert', ...
        ~any(contains([codeS codeC], banned)));
    results(end+1,:) = check('info: kind, keys, settings hash, one expected record per session, line count', ...
        infoS.Kind == "session" && infoC.Kind == "compare" && isequal(infoC.Keys, keys9) ...
        && infoS.SettingsHash == St9.Settings.hash() && numel(infoC.Expected) == 3 ...
        && infoS.NumLines == numel(codeS) && isequaln(infoC.Expected(1), infoS.Expected) ...
        && isequaln(infoC.Expected(2).Threshold, St9.result(keys9(2)).Threshold));

    s9 = localEvalSettings(codeC);
    results(end+1,:) = check('The settings statement parses back to the same settings and hash', ...
        isa(s9, 'behavior.Settings') && s9.hash() == St9.Settings.hash() ...
        && isequal(s9.toStruct(), St9.Settings.toStruct()));

    results(end+1,:) = check('write refuses a name that is not a MATLAB identifier', ...
        throwsWith(@() behavior.ScriptWriter.write(fullfile(out9, 'bad-name.m'), codeS), ...
        'behavior:ScriptWriter:InvalidName') && ~isfile(fullfile(out9, 'bad-name.m')));
    fileS = behavior.ScriptWriter.write(fullfile(out9, 'replicate_one'), codeS);
    results(end+1,:) = check('write appends .m, writes every line, and returns the absolute path', ...
        isfile(fileS) && endsWith(fileS, "replicate_one.m") ...
        && isequal(readlines(fileS, 'EmptyLineRule', 'read')', [string(codeS) ""]));
    results(end+1,:) = check('The keys the scripts load exist under the root', ...
        all(arrayfun(@(k) isfile(fullfile(root, k)), keys9)));

    outS = fullfile(out9, 'outS');
    wsS = localRunScript(fileS, root, outS);
    results(end+1,:) = check('The session script runs and replicates exactly', ...
        contains(wsS.out, "replicated exactly") && isequal(wsS.replicated, true) ...
        && isstruct(wsS.results) && isscalar(wsS.results) && wsS.results.Key == keys9(1) ...
        && ~isempty(dir(fullfile(outS, '*.csv'))));

    fileC = behavior.ScriptWriter.write(fullfile(out9, 'replicate_compare.m'), codeC);
    outC = fullfile(out9, 'outC');
    wsC = localRunScript(fileC, root, outC);
    results(end+1,:) = check('The compare script replicates all three, says so, and exports into OUTFOLDER', ...
        count(wsC.out, "replicated exactly") == 3 && contains(wsC.out, "3 of 3 sessions replicated.") ...
        && isequal(wsC.replicated, true(1, 3)) && numel(wsC.results) == 3 ...
        && isfile(fullfile(outC, 'epsych_thresholds.csv')) && contains(wsC.out, "Threshold by"));

    hashLine = find(contains(codeS, 'cfg.hash() == "'), 1);
    codeT = codeS;
    codeT{hashLine} = regexprep(codeT{hashLine}, '"[0-9a-f]{8}"', '"0badc0de"');
    fileT = behavior.ScriptWriter.write(fullfile(out9, 'replicate_tampered.m'), codeT);
    results(end+1,:) = check('A tampered settings hash stops the script with behavior:ScriptWriter:settingsHash', ...
        ~isequal(codeT, codeS) && throwsWith(@() localRunScript(fileT, root, fullfile(out9, 'outT')), ...
        'behavior:ScriptWriter:settingsHash'));

    St9.addGrouping("Treatment", ["Noise" "Control"]);
    St9.assign("Treatment", "SUBJ-ID-1234", "Noise");
    St9.assign("Treatment", "Rat_7_B", "Control");
    codeG = behavior.ScriptWriter.compare(St9, keys9, GroupBy = "manual:Treatment", ...
        Figures = false, Export = false);
    fileG = behavior.ScriptWriter.write(fullfile(out9, 'replicate_grouped.m'), codeG);
    wsG = localRunScript(fileG, root, fullfile(out9, 'outG'));
    results(end+1,:) = check('A manual grouping travels as a T.Group_ literal and the script runs with it', ...
        any(startsWith(codeG, 'T.Group_Treatment = ')) && ~any(startsWith(codeG, '%% Export')) ...
        && isequal(wsG.T.Group_Treatment, ["Noise"; "Noise"; "Control"]) ...
        && contains(wsG.out, "Threshold by Group: Treatment") && contains(wsG.out, "3 of 3 sessions replicated."));

    if exist('behavior.Plot', 'class') == 8
        before = findall(groot, 'Tag', 'EPsychBehaviorScript');
        codeF = behavior.ScriptWriter.session(St9, keys9(1), Export = false);
        codeF2 = behavior.ScriptWriter.compare(St9, keys9, Export = false, Kind = "strip");
        fileF = behavior.ScriptWriter.write(fullfile(out9, 'replicate_figure.m'), codeF);
        fileF2 = behavior.ScriptWriter.write(fullfile(out9, 'replicate_figures.m'), codeF2);
        wsF = localRunScript(fileF, root, fullfile(out9, 'outF'));
        wsF2 = localRunScript(fileF2, root, fullfile(out9, 'outF2'));
        figs = setdiff(findall(groot, 'Tag', 'EPsychBehaviorScript'), before);
        nAxes = arrayfun(@(f) numel(findall(f, 'Type', 'axes')), figs);
        delete(figs);
        results(end+1,:) = check('With Figures, both scripts draw into a figure tagged EPsychBehaviorScript', ...
            numel(figs) == 2 && all(nAxes >= 2) && contains(wsF.out, "replicated exactly") ...
            && contains(wsF2.out, "3 of 3 sessions replicated."));
    else
        fprintf('  (behavior.Plot is not on the path: the figure case was skipped)\n');
    end
    clear removeOut9
catch ME
    results(end+1,:) = check(['ScriptWriter: ' ME.message ' (' ME.stack(1).name ':' num2str(ME.stack(1).line) ')'], false);
end

%% 10. Export
try
    c10 = behavior.Catalog(root, CacheFolder = cacheDir);
    c10.scan();
    s10 = behavior.Settings();
    sims10 = manifest(strcmp({manifest.Kind}, 'sim'));
    xrc = cell(1, numel(sims10));
    for i = 1:numel(sims10)
        xrc{i} = behavior.Session.load(c10.session(sims10(i).Key)).analyze(s10);
    end
    xr = [xrc{:}];
    xT = behavior.Aggregate.thresholds(xr, c10.Sessions);
    nT = height(xT);
    xT.Group_Treatment = repmat("Control", nT, 1);
    xT.Group_Treatment(1) = "Noise";
    xT.Threshold(1) = NaN;            % a missing threshold: an empty field
    xT.ThresholdStd(2) = Inf;         % an infinity: never written

    allNames = behavior.Export.TABLES;
    Tb = behavior.Export.tables(xT, xr, Subjects = c10.Subjects);
    S10 = behavior.Export.schema();
    K10 = sum(~cellfun(@isempty, regexp(xT.Properties.VariableNames, '^Tag\d+$', 'once')));
    cols10 = @(tn) localExpectedColumns(S10, tn, K10, "treatment");
    same = isequal(string(fieldnames(Tb))', allNames);
    for tn = allNames
        same = same && isequal(string(Tb.(tn).Properties.VariableNames), cols10(tn));
    end
    results(end+1,:) = check('Every table exists with exactly the schema''s columns (tag_1, group_treatment expanded)', ...
        same && ismember("tag_1", Tb.sessions.Properties.VariableNames) ...
        && ismember("group_treatment", Tb.sessions.Properties.VariableNames) ...
        && ismember("group_treatment", Tb.subjects.Properties.VariableNames) ...
        && ~ismember("group_treatment", Tb.thresholds.Properties.VariableNames));

    nRev = sum([xr.ReversalCount]);
    nSubj = numel(unique(xT.Project + "|" + xT.Subject));
    results(end+1,:) = check('Row counts: sessions, thresholds, fits, metrics = sessions; reversals = reversal total', ...
        height(Tb.sessions) == nT && height(Tb.thresholds) == nT && height(Tb.fits) == nT ...
        && height(Tb.metrics) == nT && height(Tb.reversals) == nRev && nRev > 0 ...
        && height(Tb.subjects) == nSubj && sum(Tb.subjects.n_sessions) == nT && height(Tb.notes) == 0);
    results(end+1,:) = check('Cells carry the right things (key, file, is_test, threshold, d_prime, reversal values)', ...
        isequal(Tb.sessions.session_key, string(xT.Key)) && all(endsWith(Tb.sessions.file, ".mat")) ...
        && ~any(Tb.sessions.is_test) && isnan(Tb.thresholds.threshold(1)) ...
        && isequaln(Tb.thresholds.threshold(2:end), xT.Threshold(2:end)) ...
        && isequaln(Tb.metrics.d_prime, xT.DPrime) && Tb.metrics.n_total(1) == xr(1).Metrics.N.Total ...
        && isequal(Tb.reversals.value(Tb.reversals.session_key == string(xr(1).Key)), reshape(xr(1).ReversalValues, [], 1)) ...
        && all(Tb.fits.engine == "builtin") && isequal(Tb.fits.converged, xT.FitConverged));
    gsub = Tb.subjects.group_treatment;
    expectSub = strings(height(Tb.subjects), 1);
    for i = 1:height(Tb.subjects)
        lv = unique(xT.Group_Treatment(xT.Subject == Tb.subjects.subject(i) & xT.Project == Tb.subjects.project(i)));
        if isscalar(lv), expectSub(i) = lv; end
    end
    results(end+1,:) = check('subjects: group level only where every session agrees', ...
        isequal(gsub, expectSub) && any(gsub == "") && any(gsub == "Control"));
    only = behavior.Export.tables(xT, xr, Tables = ["thresholds" "metrics"]);
    results(end+1,:) = check('Tables= limits what is built', isequal(string(fieldnames(only))', ["thresholds" "metrics"]));

    out10 = fullfile(base, 'export10');
    cleanup10 = onCleanup(@() localRemoveDir(out10));
    files = behavior.Export.write(Tb, out10, Formats = ["csv" "xlsx" "mat"]);
    expectFiles = [arrayfun(@(t) "epsych_" + t + ".csv", allNames), "epsych_columns.csv", "epsych_tables.xlsx", "epsych_export.mat"];
    results(end+1,:) = check('write: one CSV per table, the columns file, the XLSX and the MAT', ...
        isequal(sort(extractAfter(files, strlength(out10) + 1))', sort(expectFiles)) && all(isfile(files)));

    bad = false;
    for f = files(endsWith(files, ".csv"))'
        txt = fileread(f);
        bad = bad || contains(txt, "NaN") || contains(txt, "Inf") || contains(txt, "null");
    end
    results(end+1,:) = check('No CSV contains NaN, Inf or null', ~bad);

    opts = detectImportOptions(fullfile(out10, 'epsych_thresholds.csv'));
    opts = setvartype(opts, opts.VariableNames, 'string');
    raw = readtable(fullfile(out10, 'epsych_thresholds.csv'), opts);
    Th = readtable(fullfile(out10, 'epsych_thresholds.csv'), 'TextType', 'string');
    results(end+1,:) = check('A NaN threshold and an infinite std are empty fields', ...
        (ismissing(raw.threshold(1)) || raw.threshold(1) == "") ...
        && (ismissing(raw.threshold_std(2)) || raw.threshold_std(2) == "") && ~ismissing(raw.threshold(2)) ...
        && raw.threshold(2) ~= "");
    results(end+1,:) = check('readtable of thresholds: height(T) rows, numeric threshold, ISO start_time', ...
        height(Th) == nT && isnumeric(Th.threshold) && isnan(Th.threshold(1)) ...
        && abs(Th.threshold(2) - xT.Threshold(2)) < 1e-8 * max(1, abs(xT.Threshold(2))) ...
        && ~isempty(regexp(raw.start_time(1), '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$', 'once')));
    sessionsText = fileread(fullfile(out10, 'epsych_sessions.csv'));
    results(end+1,:) = check('Logicals are TRUE/FALSE in the text', ...
        contains(sessionsText, "FALSE") && ~contains(sessionsText, "false"));

    D10 = behavior.Export.dictionary(Tb);
    Dc = readtable(fullfile(out10, 'epsych_columns.csv'), 'TextType', 'string');
    parts = arrayfun(@(tn) tn + "." + reshape(string(Tb.(tn).Properties.VariableNames), [], 1), ...
        allNames, 'UniformOutput', false);
    written = vertcat(strings(0, 1), parts{:});
    results(end+1,:) = check('dictionary rows equal the union of written columns (and the columns file says so)', ...
        isequal(D10.Table + "." + D10.Column, written) && height(Dc) == height(D10) ...
        && isequal(Dc.Column, D10.Column) && all(strlength(D10.Meaning) > 0) ...
        && any(D10.Column == "group_treatment") && any(D10.Column == "tag_1"));

    sheets = reshape(string(sheetnames(fullfile(out10, 'epsych_tables.xlsx'))), 1, []);
    L = load(fullfile(out10, 'epsych_export.mat'));
    results(end+1,:) = check('XLSX has a sheet per table; MAT holds EPsychExport equal to the tables', ...
        isequal(sort(sheets), sort(allNames)) && isstruct(L.EPsychExport) ...
        && isequaln(L.EPsychExport, Tb));

    tsv = behavior.Export.toTSV(Tb.thresholds);
    tl = splitlines(tsv);
    results(end+1,:) = check('toTSV: height + 1 lines, one tab fewer than columns per line', ...
        numel(tl) == nT + 1 && all(count(tl, char(9)) == width(Tb.thresholds) - 1));
    tfc = behavior.Export.copyTable(Tb.thresholds);
    results(end+1,:) = check('copyTable does not throw (and says whether it copied)', islogical(tfc) && isscalar(tfc));

    emptyT = behavior.Aggregate.thresholds([]);
    Tb0 = behavior.Export.tables(emptyT, []);
    ok0 = true;
    for tn = allNames
        ok0 = ok0 && height(Tb0.(tn)) == 0 && isequal(string(Tb0.(tn).Properties.VariableNames), ...
            localExpectedColumns(S10, tn, 1, strings(0, 1)));
    end
    out0 = fullfile(base, 'export10_empty');
    cleanup0 = onCleanup(@() localRemoveDir(out0));
    files0 = behavior.Export.write(Tb0, out0);
    hdr = fileread(fullfile(out0, 'epsych_thresholds.csv'));
    results(end+1,:) = check('An empty T and results give empty tables with the columns; write still writes the headers', ...
        ok0 && numel(files0) == numel(allNames) + 1 ...
        && strcmp(strtrim(hdr), strjoin(localExpectedColumns(S10, "thresholds", 1, strings(0, 1)), ",")) ...
        && isscalar(splitlines(strtrim(hdr))));
    results(end+1,:) = check('write refuses an unknown format', ...
        throwsWith(@() behavior.Export.write(Tb0, out0, Formats = "pdf"), 'behavior:Export:UnknownFormat'));
    clear cleanup10 cleanup0
catch ME
    results(end+1,:) = check(['Export: ' ME.message ' (' ME.stack(1).name ':' num2str(ME.stack(1).line) ')'], false);
end

%% 11. roster enrichment
try
    rosterFile = fullfile(base, 'roster', 'smoke.esub');
    mkdir(fileparts(rosterFile));
    R = epsych.SubjectRoster(rosterFile);
    pid = R.addProject('ProjA');
    s1 = R.addSubject(struct('Name', 'SUBJ-ID-1234', 'Sex', 'Female', 'Species', 'Gerbil'));
    s2 = R.addSubject(struct('Name', 'Rat_7_B', 'Sex', 'Male', 'Species', 'Rat'));
    R.assign(s1, pid);
    R.assign(s2, pid);
    R.updateSubject(s2, struct('Name', 'Rat7B'));     % its data folder keeps the old name

    setpref('ep_RunExpt_Subjects', 'RosterFile', rosterFile);
    c.applyRoster();
    U = c.Subjects;
    a = U(U.Subject == "SUBJ-ID-1234", :);
    b = U(U.Subject == "Rat_7_B", :);
    m = U(U.Subject == "M01", :);
    results(end+1,:) = check('applyRoster reads the configured roster', ...
        c.RosterFile == string(rosterFile) && isa(c.Roster, 'epsych.SubjectRoster'));
    results(end+1,:) = check('A subject in the roster is known by its current name', ...
        a.RosterKnown && a.RosterNameMatch == "current" && a.RosterSex == "Female" ...
        && a.RosterSpecies == "Gerbil" && contains(a.RosterProjects, "ProjA") && ~a.RosterRetired);
    results(end+1,:) = check('A renamed subject is known by its former name', ...
        b.RosterKnown && b.RosterNameMatch == "former" && b.RosterSpecies == "Rat");
    results(end+1,:) = check('A subject the roster lacks is not known', ...
        ~any(m.RosterKnown) && all(m.RosterNameMatch == "") ...
        && ~U.RosterKnown(U.Subject == "SUBJ-ID-959"));

    c.scan();
    results(end+1,:) = check('A rescan keeps the roster columns', ...
        ismember("RosterKnown", c.Subjects.Properties.VariableNames) ...
        && sum(c.Subjects.RosterKnown) == 2);

    rmpref('ep_RunExpt_Subjects', 'RosterFile');
    c.applyRoster();
    U = c.Subjects;
    cols = ["RosterKnown" "RosterSex" "RosterSpecies" "RosterProjects" "RosterLastProtocol" ...
        "RosterLastProtocolVersion" "RosterRetired" "RosterNameMatch"];
    results(end+1,:) = check('With no roster configured the columns are present and all false', ...
        all(ismember(cols, U.Properties.VariableNames)) && ~any(U.RosterKnown) ...
        && all(U.RosterNameMatch == "") && c.RosterFile == "" && isempty(c.Roster));
    results(end+1,:) = check('applyRoster did not create the preference it reads', ...
        ~ispref('ep_RunExpt_Subjects', 'RosterFile'));
catch ME
    results(end+1,:) = check(['roster: ' ME.message], false);
end

% --- Report ------------------------------------------------------------------
labels = results(:,1);
passed = [results{:,2}];
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', sum(passed), sum(~passed), numel(passed));

clear restorePrefs removeBase
if any(~passed)
    error('smoke_test_behavior_model:Failed', '%d smoke test(s) failed.', sum(~passed));
end

end




%% =========================================================================
function [root, manifest] = localMakeRoot(folder)
% [root, manifest] = localMakeRoot(folder)
% A synthetic data root under folder, named LabRoot, and a manifest of every
% file written: File, Key, Kind, Listed (a scan should list it), IsSession,
% Project, Subject, Tags, Collision, Start, Sex, Species.
%
% Kinds: sim (an ordinary simulated session), legacy, placeholder, corrupt,
% test, mismatch, nostamp, analysis, skipped.

root = fullfile(folder, 'LabRoot');
mkdir(root);

A = 'ProjA'; B = 'ProjB';
gerbilF = {'Female', 'Gerbil'};
ratM = {'Male', 'Rat'};
mouseM = {'Male', 'Mouse'};

% --- ProjA / SUBJ-ID-1234 -----------------------------------------------
specs = {
    % project subject         stamp            tags              collision seed
    A, 'SUBJ-ID-1234', '261001T100000', ["Pre" "Passive"],  "",  1
    A, 'SUBJ-ID-1234', '261002T100000', ["Pre" "Active"],   "",  2
    A, 'SUBJ-ID-1234', '261008T100000', ["Post" "Passive"], "",  3
    A, 'SUBJ-ID-1234', '261008T100000', ["Post" "Active"],  "A", 4
    A, 'SUBJ-ID-959',  '261001T120000', ["Pre" "Passive"],  "",  5
    A, 'Rat_7_B',      '261001T110000', ["Pre" "Passive"],  "",  6
    A, 'Rat_7_B',      '261008T110000', ["Post" "Active"],  "",  7
    B, 'M01',          '261001T090000', ["Pre" "Passive"],  "",  8
    B, 'M01',          '261008T090000', ["Post" "Passive"], "",  9
    '', 'M01',         '261015T090000', ["Post" "Active"],  "", 10
    };
simEntries = cell(1, size(specs, 1));
for i = 1:size(specs, 1)
    [proj, subj, stamp, tags, coll, seed] = specs{i,:};
    who = localWho(subj, gerbilF, ratM, mouseM);
    name = strjoin([string(subj), string(stamp), coll(coll ~= ""), tags], "_") + ".mat";
    t0 = datetime(stamp, 'InputFormat', 'yyMMdd''T''HHmmss');
    Data = localSimData(80, seed, t0, false);
    Info = localInfo(t0, subj, who{:}, false);
    simEntries{i} = localWrite(root, proj, subj, name, Data, Info, 'sim', tags, coll, t0, who);
end
manifest = [simEntries{:}];

% A legacy session: Data only, named by date.
t0 = datetime(2026,8,5,10,0,0);
Data = localSimData(40, 11, t0, false);
manifest(end+1) = localWrite(root, A, 'SUBJ-ID-1234', "SUBJ-ID-1234_05-Aug-2026.mat", ...
    Data, [], 'legacy', strings(1,0), "", datetime(2026,8,5), gerbilF);

% Somebody's analysis beside the sessions.
x = magic(4);
f = fullfile(root, A, 'SUBJ-ID-1234', 'analysis.mat');
save(f, 'x');
manifest(end+1) = localEntry(root, f, 'analysis', true, false, A, 'SUBJ-ID-1234');

% Never listed: a hidden folder, and the analysis store.
t0 = datetime(2026,10,3,10,0,0);
Data = localSimData(30, 12, t0, false);
Info = localInfo(t0, 'SUBJ-ID-1234', gerbilF{:}, false);
manifest(end+1) = localWrite(root, fullfile(A, 'SUBJ-ID-1234', '.hidden'), '', ...
    "SUBJ-ID-1234_261003T100000_Pre.mat", Data, Info, 'skipped', "Pre", "", t0, gerbilF);
manifest(end).Listed = false;
manifest(end+1) = localWrite(root, 'EPsych_Analysis', '', "stray_261003T100000.mat", ...
    Data, Info, 'skipped', strings(1,0), "", t0, gerbilF);
manifest(end).Listed = false;

% A Preview session.
t0 = datetime(2026,10,10,11,0,0);
Data = localSimData(50, 13, t0, true);
Info = localInfo(t0, 'Rat_7_B', ratM{:}, true);
manifest(end+1) = localWrite(root, A, 'Rat_7_B', "Rat_7_B_261010T110000_Post_Active.mat", ...
    Data, Info, 'test', ["Post" "Active"], "", t0, ratM);

% A session that completed nothing: one record, every field empty.
t0 = datetime(2026,10,11,11,0,0);
Data = struct('Depth', [], 'RespCode', [], 'TrialType', [], 'TrialIndex', [], ...
    'TrialID', [], 'computerTimestamp', [], 'isTest', []);
Info = localInfo(t0, 'Rat_7_B', ratM{:}, false);
manifest(end+1) = localWrite(root, A, 'Rat_7_B', "Rat_7_B_261011T110000_Post.mat", ...
    Data, Info, 'placeholder', "Post", "", t0, ratM);

% Not a MAT file at all, as a save interrupted by a crash can leave.
f = fullfile(root, B, 'M01', 'M01_261012T090000_Post.mat');
fid = fopen(f, 'w'); fwrite(fid, 'not a mat file'); fclose(fid);
e = localEntry(root, f, 'corrupt', true, true, B, 'M01');
e.Tags = "Post";
e.Start = datetime(2026,10,12,9,0,0);
manifest(end+1) = e;

% Saved under a name that is not the folder's.
t0 = datetime(2026,10,13,9,0,0);
Data = localSimData(60, 14, t0, false);
Info = localInfo(t0, 'M01', mouseM{:}, false);
manifest(end+1) = localWrite(root, B, 'M01', "M1_261013T090000_Pre_Active.mat", ...
    Data, Info, 'mismatch', ["Pre" "Active"], "", t0, mouseM);

% A name with no stamp: the start comes from the snapshot.
t0 = datetime(2026,10,14,9,0,0);
Data = localSimData(60, 15, t0, false);
Info = localInfo(t0, 'M01', mouseM{:}, false);
manifest(end+1) = localWrite(root, B, 'M01', "M01_session3.mat", ...
    Data, Info, 'nostamp', strings(1,0), "", t0, mouseM);

end


function who = localWho(subj, gerbilF, ratM, mouseM)
switch subj
    case 'Rat_7_B', who = ratM;
    case 'M01',     who = mouseM;
    otherwise,      who = gerbilF;
end
end


function e = localWrite(root, proj, subj, name, Data, Info, kind, tags, coll, start, who)
% Save one session (Info omitted when empty) and describe it for the manifest.
folder = fullfile(root, proj, subj);
if ~isfolder(folder), mkdir(folder); end
f = fullfile(folder, char(name));
if isempty(Info)
    save(f, 'Data');
else
    save(f, 'Data', 'Info');
end
e = localEntry(root, f, kind, true, true, proj, subj);
e.Tags = reshape(string(tags), 1, []);
e.Collision = string(coll);
e.Start = start;
e.Sex = string(who{1});
e.Species = string(who{2});
end


function e = localEntry(root, f, kind, listed, isSession, proj, subj)
e = struct('File', "", 'Key', "", 'Kind', '', 'Listed', false, 'IsSession', false, ...
    'Project', "", 'Subject', "", 'Tags', strings(1,0), 'Collision', "", ...
    'Start', NaT, 'Sex', "", 'Species', "");
if nargin == 0, return, end
e.File = string(f);
e.Key = behavior.Catalog.keyFor(root, f);
e.Kind = kind;
e.Listed = listed;
e.IsSession = isSession;
if isempty(proj)
    [~, rootName] = fileparts(root);
    e.Project = string(rootName);
else
    e.Project = string(proj);
end
e.Subject = string(subj);
end


function Data = localSimData(nTrials, seed, t0, isTest)
% A simulated 1-up/1-down staircase on Depth: a hit steps Depth down, a miss
% steps it up, so the track hovers around the observer's 50% point (mu). Every
% 7th trial is a catch (TrialType 1, no stimulus), every 10th a reminder
% (TrialType 2, at a depth the observer always hears). As the runtime does,
% the trial type's TrialType_k bit is set in RespCode as well as its outcome.
% A private stream keeps the global one untouched.

rs = RandStream('mt19937ar', 'Seed', seed);
HIT  = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS = bitset(uint32(0), uint32(epsych.BitMask.Miss));
CR   = bitset(uint32(0), uint32(epsych.BitMask.CorrectReject));
FA   = bitset(uint32(0), uint32(epsych.BitMask.FalseAlarm));
TT0  = uint32(epsych.BitMask.TrialType_0);

mu = 20; sigma = 4; step = 2;
depth = 32;
Data = repmat(struct('Depth', [], 'RespCode', [], 'TrialType', [], 'TrialIndex', [], ...
    'TrialID', [], 'computerTimestamp', NaT, 'isTest', false), 1, nTrials);
for k = 1:nTrials
    if mod(k, 7) == 0
        tt = 1; level = 0;
        if rand(rs) < 0.15, out = FA; else, out = CR; end
    elseif mod(k, 10) == 0
        tt = 2; level = 50; out = HIT;
    else
        tt = 0; level = depth;
        if rand(rs) < normcdf((depth - mu) / sigma)
            out = HIT; depth = depth - step;
        else
            out = MISS; depth = depth + step;
        end
    end
    Data(k).Depth = level;
    Data(k).RespCode = double(bitset(out, TT0 + tt));
    Data(k).TrialType = tt;
    Data(k).TrialIndex = k;
    Data(k).TrialID = tt + 1;
    Data(k).computerTimestamp = t0 + seconds(6 * k);
    Data(k).isTest = isTest;
end
end


function info = localInfo(t0, subject, sex, species, isTest)
% Enough of an epsych.SessionSnapshot for the catalog: FormatVersion makes it
% a snapshot, Subject an epsych.Subject, and the protocol's InterfaceData the
% parameters as hw.Parameter.toStruct writes them (an infinite bound as text).
subj = epsych.DefaultSubject(struct('BoxID', 1, 'Name', subject, 'Sex', sex, 'Species', species));
pars = {localParameter('Depth', 'dB', 0, 60, 'Float'), ...
        localParameter('ITI', 's', 0, "Inf", 'Float'), ...
        localParameter('Reward', '', 0, 1, 'Boolean')};
module = struct('Label', 'Behavior', 'Name', 'Behavior', 'Index', 1, 'Fs', 1, ...
    'Info', '', 'Parameters', {pars});
iface = struct('Type', 'Software', 'ClassName', 'hw.Software', 'Modules', {{module}});
protocol = struct('Options', struct('trialFunc', 'smoke_trialFunc'), ...
    'protocolVersion', 'v3.261001', 'InterfaceData', {{iface}});
info = struct( ...
    'FormatVersion', epsych.SessionSnapshot.FORMAT_VERSION, ...
    'EPsychMeta',    struct('LatestTag', 'v9.9.9', 'Checksum', 'abcdef1234567890'), ...
    'Subject',       subj, ...
    'BoxID',         1, ...
    'isTest',        isTest, ...
    'DataFilename',  '', ...
    'StartTime',     t0, ...
    'SelectorClass', '', ...
    'Protocol',      protocol, ...
    'TrialTable',    {{}}, ...
    'WriteParams',   {{}}, ...
    'WriteParamIdx', struct(), ...
    'Notes',         epsych.SessionNotes.emptyRecords(), ...
    'NotesText',     '', ...
    'NotesEdited',   false);
end


function p = localParameter(name, unit, lo, hi, type)
p = struct('Name', name, 'Description', '', 'Unit', unit, 'Access', 'Read / Write', ...
    'Type', type, 'Format', '%g', 'Visible', true, 'UpdateEveryTrial', true, ...
    'SetOnce', false, 'PersistWithPhase', true, 'Values', {{lo}}, 'Value', lo, ...
    'lastUpdated', NaT, 'isArray', false, 'isTrigger', false, 'isRandom', false, ...
    'Min', lo, 'Max', hi, 'UserData', [], 'Expression', '');
end


function tf = localHas(S, key, flag)
% Whether the session with this key carries this QCFile flag.
k = find(behavior.Catalog.keyEquals(S.Key, key));
tf = isscalar(k) && any(S.QCFile{k} == flag);
end


function T = localListing(root)
% Every file and folder under root with its size and modification time: what
% "the scan wrote nothing under root" is checked against.
L = dir(fullfile(root, '**', '*'));
L = L(~ismember({L.name}, {'.', '..'}));
T = table(reshape(string(fullfile({L.folder}, {L.name})), [], 1), ...
    reshape([L.bytes], [], 1), reshape([L.datenum], [], 1), ...
    'VariableNames', {'Path', 'Bytes', 'Modified'});
T = sortrows(T, 'Path');
end


function x = localBoom(Data, ~)
% An Extra callback that fails part way, as a buggy analysis callback would.
x = struct('N', numel(Data));
if x.N >= 0
    error('smoke:boom', 'boom');
end
end


function st = localReverseFields(st)
% The same settings struct with every level's fields in reverse order.
names = flip(fieldnames(st));
st = orderfields(st, names);
for k = 1:numel(names)
    if isstruct(st.(names{k})) && isscalar(st.(names{k}))
        st.(names{k}) = localReverseFields(st.(names{k}));
    end
end
end


function tf = localNoEdit(root, fcn)
% Whether an edit that changes nothing leaves a freshly opened project clean.
Q = behavior.Project.open(root);
fcn(Q);
tf = ~Q.Dirty;
end


function tf = localSameFile(file, fcn)
% Whether running fcn leaves a file's bytes and modification time as they were.
d0 = dir(file);
b0 = localBytes(file);
fcn();
d1 = dir(file);
tf = isscalar(d1) && isequal(b0, localBytes(file)) && d0.datenum == d1.datenum;
end


function b = localBytes(file)
fid = fopen(file, 'r');
b = fread(fid, Inf, '*uint8');
fclose(fid);
end


function cols = localExpectedColumns(S, tableName, numTags, groups)
% The columns the schema promises for one table, placeholders expanded.
rows = reshape(S.Column(S.Table == tableName), 1, []);
parts = cell(1, numel(rows));
for i = 1:numel(rows)
    r = rows(i);
    if r == "tag_<k>"
        parts{i} = "tag_" + (1:numTags);
    elseif r == "group_<name>"
        parts{i} = "group_" + reshape(groups, 1, []);
    else
        parts{i} = r;
    end
end
cols = [strings(1, 0), parts{:}];
end



function tf = localInOrder(code, heads)
% Each heading starts a line, after the one before it.
at = arrayfun(@(h) find(startsWith(code, h), 1), heads, 'UniformOutput', false);
tf = all(~cellfun(@isempty, at)) && all(diff([at{:}]) > 0);
end


function s = localEvalSettings(code)
% The script's settings statement, evaluated on its own.
i0 = find(startsWith(code, 'cfg = behavior.Settings('), 1);
i1 = i0 - 1 + find(endsWith(code(i0:end), ');'), 1);
% Evaluated as an expression: a variable named settings, created by eval, is
% not seen as one in a function (MATLAB has a settings function).
s = eval(regexprep(strjoin(code(i0:i1), newline), '^cfg = |;$', ''));
end


function ws = localRunScript(file, root, outFolder)
% Run a generated script the way a reader would, with ROOT and OUTFOLDER set
% first, and hand back its workspace (out = what it printed).
out = evalc(['ROOT = ' behavior.ScriptWriter.literal(string(root)) '; ' ...
    'OUTFOLDER = ' behavior.ScriptWriter.literal(string(outFolder)) '; ' ...
    'run(' behavior.ScriptWriter.literal(char(file)) ');']);
ws = struct('out', out);
for v = reshape(setdiff(who, {'ws', 'out', 'file', 'root', 'outFolder'}), 1, [])
    ws.(v{1}) = eval(v{1});
end
end


function row = check(label, tf)
row = {char(label), logical(tf)};
end


function tf = throwsWith(fcn, identifier)
tf = false;
try
    fcn();
catch ME
    tf = strcmp(ME.identifier, identifier);
end
end


function saved = localSavePref(group, name)
saved = struct('group', group, 'name', name, 'existed', ispref(group, name), 'value', []);
if saved.existed
    saved.value = getpref(group, name);
end
end


function localRestorePref(saved)
if saved.existed
    setpref(saved.group, saved.name, saved.value);
elseif ispref(saved.group, saved.name)
    rmpref(saved.group, saved.name);
end
end


function localRemoveDir(folder)
if isfolder(folder)
    try
        rmdir(folder, 's');
    catch ME
        vprintf(2, ME);
    end
end
end
