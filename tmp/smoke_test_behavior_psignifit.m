function smoke_test_behavior_psignifit()
% smoke_test_behavior_psignifit
% Standing proof of the psignifit fitting engine in the offline behavioral
% analysis (behavior.fit.Psignifit, behavior.fit.PsignifitPlot, the
% Settings.Psignifit group, the Settings dialog's psignifit page and the Fit
% tab of epsych.BehaviorAnalysis):
%    1  finding psignifit: locate/available/version/directions, setFolder
%       refusing a folder with no psignifit, and the "missing" path
%       (behavior.fit.Psignifit.override) reported without throwing
%    2  Settings.Psignifit: defaults are psignifit's, the hash ignores the
%       group under the built-in engine (so no earlier hash moved), JSON round
%       trip, strict and forgiving validation, problems()
%    3  psignifitOptions: the one translation (neg_ sigmoid for an Up
%       staircase, nAFC, absolute criterion, catch-trial guess rate, grids)
%    4  psychophysics.Staircase.psychometricCounts is exactly what
%       fitPsychometric fits
%    5  fromCounts: the same numbers psignifit itself gives, a log-axis
%       sigmoid in stimulus units, an absolute criterion through
%       getThreshold, refusals as messages, warnings captured not printed,
%       an edge-of-grid threshold not identifiable
%    6  the cache: a repeat is a hit, on disk under the cache folder, and
%       UseCache=false gives the same numbers
%    7  Session.analyze with psignifit, Aggregate and the fits export
%    8  PsignifitPlot: psignifit's plots into a uiaxes of a hidden uifigure
%       with no stray window, the window state restored, the random stream
%       untouched; the whole-figure plots in windows of their own
%    9  the Settings dialog's psignifit page: status, engine switch, greyed
%       options, Apply into the project file; the missing state
%   10  the Fit tab and the Session tab draw psignifit's plots; a generated
%       script names psignifit and replicates the fit exactly
%
% Groups 3-10 need psignifit (https://github.com/wichmann-lab/psignifit);
% without it they are skipped, and only the missing path is proved.
%
%   run('tmp/smoke_test_behavior_psignifit.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('epsych.BitMask', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);
pid = feature('getpid');
root = fullfile(tempdir, sprintf('epsych_psignifit_root_%d', pid));
cache = fullfile(tempdir, sprintf('epsych_psignifit_cache_%d', pid));
store = fullfile(tempdir, sprintf('epsych_psignifit_store_%d', pid));
out = fullfile(tempdir, sprintf('epsych_psignifit_out_%d', pid));
for d = {root, cache, store, out}
    if isfolder(d{1}), rmdir(d{1}, 's'); end
end
mkdir(out);

PREF = 'epsych2_BehaviorAnalysis';
saved = {localSavePrefs(PREF), localSavePrefs('epsych2_psychophysics_Staircase')};
hadPsPref = ispref('EPsych', 'PsignifitPath');
if hadPsPref, psPref = getpref('EPsych', 'PsignifitPath'); else, psPref = ''; end
restorePrefs = onCleanup(@() localRestorePrefs(saved, hadPsPref, psPref));
removeFolders = onCleanup(@() localRemove({root, cache, store, out}));
closeWindows = onCleanup(@localCloseWindows);
noOverride = onCleanup(@() behavior.fit.Psignifit.override(""));
localCloseWindows();

%% Fixture: one subject, two sessions of a 1-up/1-down track converging on 20 dB
mkdir(fullfile(root, 'ProjP', 'P1'));
day0 = datetime(2026, 10, 1, 9, 0, 0);
for i = 1:2
    Data = localObserverData(200, 20, 700 + i);
    stamp = string(day0 + days(i - 1), 'yyMMdd''T''HHmmss');
    save(fullfile(root, 'ProjP', 'P1', sprintf('P1_%s_Pre.mat', stamp)), 'Data');
end

%% 1. Finding psignifit
try
    L = behavior.fit.Psignifit.locate(Refresh = true);
    have = behavior.fit.Psignifit.available();
    results(end+1,:) = check('locate answers Found, Folder, Source, Version, Searched', ...
        all(isfield(L, {'Found' 'Folder' 'Source' 'Version' 'Searched'})) && L.Found == have);
    txt = behavior.fit.Psignifit.directions();
    results(end+1,:) = check('directions name the GitHub page, the clone URL and the preference', ...
        any(contains(txt, behavior.fit.Psignifit.URL)) && any(contains(txt, "git clone")) ...
        && any(contains(txt, "PsignifitPath")));
    bad = fullfile(tempdir, sprintf('not_psignifit_%d', pid));
    mkdir(bad);
    threw = "";
    try
        behavior.fit.Psignifit.setFolder(bad, Remember = false);
    catch ME
        threw = string(ME.identifier);
    end
    rmdir(bad);
    results(end+1,:) = check('setFolder refuses a folder with no psignifit, changing nothing', ...
        threw == "behavior:fit:Psignifit:NotAnInstall" && behavior.fit.Psignifit.available() == have ...
        && ispref('EPsych', 'PsignifitPath') == hadPsPref);

    behavior.fit.Psignifit.override("missing");
    why = behavior.fit.Psignifit.whyUnavailable();
    s = behavior.Settings(Fit = struct(Engine = "psignifit"));
    p = s.problems();
    sess = behavior.Session.load(localFirstSession(root, cache), Root = root);
    Rm = sess.analyze(s);
    behavior.fit.Psignifit.override("");
    results(end+1,:) = check('missing: whyUnavailable says where to get it, problems() blocks, analyze does not throw', ...
        contains(why, behavior.fit.Psignifit.URL) && isscalar(p) && startsWith(p, "psignifit: ") ...
        && Rm.Fit.Engine == "psignifit" && any(Rm.QC == "fit_failed") && contains(Rm.Fit.Message, "not installed") ...
        && ~isempty(Rm.Fit.Levels) && isfinite(Rm.Threshold));
    if have
        results(end+1,:) = check('installed: whyUnavailable is empty and the version is a commit or ""', ...
            behavior.fit.Psignifit.whyUnavailable() == "" && (L.Version == "" || strlength(L.Version) == 7));
        L2 = behavior.fit.Psignifit.setFolder(L.Folder, Remember = false);
        results(end+1,:) = check('setFolder on the found folder (Remember=false) keeps it and writes no preference', ...
            L2.Found && L2.Folder == L.Folder && ispref('EPsych', 'PsignifitPath') == hadPsPref);
        p = string(strsplit(path, pathsep));
        results(end+1,:) = check('psignifit sits after EPsych on the path, so it shadows nothing of EPsych''s', ...
            find(strcmpi(p, L.Folder), 1) > find(strcmpi(p, repoRoot), 1));
    end
catch ME
    results(end+1,:) = check(['group 1 threw: ' ME.message], false);
    have = false;
end

if ~have
    fprintf('\npsignifit is not installed here: groups 3-10 skipped (%s).\n', behavior.fit.Psignifit.URL);
end

%% 2. Settings.Psignifit
try
    s0 = behavior.Settings();
    d = s0.Psignifit;
    results(end+1,:) = check('defaults are psignifit''s own (norm, YesNo, MAP, 0.5, 0.95, percentiles, betaPrior 10, 25 blocks)', ...
        d.Sigmoid == "norm" && d.ExpType == "YesNo" && d.EstimateType == "MAP" && d.ThresholdPC == 0.5 ...
        && d.ConfidenceLevel == 0.95 && d.CIMethod == "percentiles" && d.BetaPrior == 10 ...
        && d.MaxBlocks == 25 && isempty(d.StimulusRange) && d.Grid == "standard");
    s1 = s0;
    s1.Psignifit = struct(Sigmoid = "logistic", StimulusRange = [0 60]);
    results(end+1,:) = check('under the built-in engine the psignifit options leave the hash alone', ...
        s1.hash() == s0.hash() && s0.hash() == "c0ddb2c2");
    s2 = s1;
    s2.Fit = struct(Engine = "psignifit");
    s3 = s2;
    s3.Psignifit = struct(Sigmoid = "gumbel");
    results(end+1,:) = check('under psignifit they are part of it', s2.hash() ~= s1.hash() && s3.hash() ~= s2.hash());
    st = s2.toStruct();
    back = behavior.Settings.fromStruct(jsondecode(jsonencode(st)));
    results(end+1,:) = check('toStruct -> JSON -> fromStruct keeps the psignifit options (StimulusRange too)', ...
        isequal(back.toStruct(), st) && back.hash() == s2.hash() && isequal(back.Psignifit.StimulusRange, [0 60]));
    e1 = localThrows(@() behavior.Settings(Psignifit = struct(StimulusRange = [5 1])));
    e2 = localThrows(@() behavior.Settings(Psignifit = struct(Sigmoid = "banana")));
    e3 = localThrows(@() behavior.Settings(Psignifit = struct(BetaPrior = 0)));
    results(end+1,:) = check('strict: a decreasing range, an unknown sigmoid, a zero beta prior are errors', ...
        e1 == "behavior:Settings:InvalidValue" && e2 == "behavior:Settings:InvalidValue" ...
        && e3 == "behavior:Settings:InvalidValue");
    raw = st;
    raw.Psignifit.Grid = "huge";
    raw.Psignifit.Bogus = 1;
    [f, w] = behavior.Settings.fromStruct(raw);
    results(end+1,:) = check('forgiving: a bad value keeps its default, an unknown field is ignored, both reported', ...
        f.Psignifit.Grid == "standard" && numel(w) == 2);
    old = rmfield(st, 'Psignifit');
    f = behavior.Settings.fromStruct(old);
    results(end+1,:) = check('a project saved before the group existed reads with psignifit''s defaults', ...
        isequal(f.Psignifit, d));
    if have
        pA = behavior.Settings(Fit = struct(Engine = "psignifit"), ...
            Psignifit = struct(GammaMode = "fixed", GammaValue = 0.6, LambdaMode = "fixed", LambdaValue = 0.5)).problems();
        pB = behavior.Settings(Fit = struct(Engine = "psignifit"), ...
            Psignifit = struct(Sigmoid = "weibull", StimulusRange = [-10 10])).problems();
        pC = behavior.Settings(Fit = struct(Engine = "psignifit", ThresholdCriterion = 0.99, ...
            CriterionScale = "absolute", LapseRate = 0.2)).problems();
        results(end+1,:) = check('problems(): no span, a log-axis range below zero; the built-in options are not checked under psignifit', ...
            any(contains(pA, "no span")) && any(contains(pB, "positive")) && isempty(pC));
    end
catch ME
    results(end+1,:) = check(['group 2 threw: ' ME.message], false);
end

if have
%% 3. psignifitOptions
try
    s = behavior.Settings(Fit = struct(Engine = "psignifit"));
    [o, info] = s.psignifitOptions();
    results(end+1,:) = check('every option is stated, psignifit''s defaults with a free YesNo guess rate', ...
        string(o.sigmoidName) == "norm" && string(o.expType) == "YesNo" && o.threshPC == 0.5 ...
        && isequal(o.stepN, [40 40 20 20 20]) && isequal(o.mbStepN, [25 30 10 10 15]) ...
        && all(isnan(o.fixedPars)) && ~isfield(o, 'stimulusRange') && info.GammaSource == "estimated" ...
        && all(isfield(o, {'confP' 'CImethod' 'widthalpha' 'betaPrior' 'nblocks' 'poolxTol' 'poolMaxGap' ...
            'poolMaxLength' 'moveBorders' 'dynamicGrid' 'gridSetType' 'maxBorderValue'})));
    s.Staircase = struct(Direction = "Up");
    o = s.psignifitOptions();
    results(end+1,:) = check('an Up staircase fits the decreasing (neg_) sigmoid', string(o.sigmoidName) == "neg_norm");
    s = behavior.Settings(Fit = struct(Engine = "psignifit"), ...
        Psignifit = struct(ExpType = "nAFC", ExpN = 3, Grid = "coarse", GammaMode = "fixed", GammaValue = 0.2));
    [o, info] = s.psignifitOptions();
    results(end+1,:) = check('nAFC: expN, a single guess-rate grid point, the guess rate left to psignifit', ...
        o.expN == 3 && o.stepN(4) == 1 && o.mbStepN(4) == 1 && isnan(o.fixedPars(4)) && info.GammaSource == "1/N");
    s = behavior.Settings(Fit = struct(Engine = "psignifit"), ...
        Psignifit = struct(GammaMode = "catch", LambdaMode = "fixed", LambdaValue = 0.02, ...
        EtaMode = "fixed", EtaValue = 0, CriterionScale = "absolute", ThresholdPC = 0.75, StimulusRange = [0 60]));
    [o, info] = s.psignifitOptions(CatchFalseAlarmRate = 0.12);
    [o2, info2] = s.psignifitOptions(CatchFalseAlarmRate = NaN);
    results(end+1,:) = check('catch guess rate, fixed lapse and eta, absolute criterion fitted at 0.5, a stated range', ...
        isequal(o.fixedPars(3:5)', [0.02 0.12 0]) && info.GammaSource == "catch" && o.threshPC == 0.5 ...
        && info.Criterion == 0.75 && isequal(o.stimulusRange, [0 60]) ...
        && isnan(o2.fixedPars(4)) && info2.GammaSource == "estimated (no usable catch trials)");
catch ME
    results(end+1,:) = check(['group 3 threw: ' ME.message], false);
end

%% 4. psychometricCounts is what fitPsychometric fits
try
    Data = localObserverData(200, 20, 42);
    S = psychophysics.Staircase(Data, 'Depth');
    results(end+1,:) = localCountsCheck(S, true);
    [row, C] = localCountsCheck(S, false);
    results(end+1,:) = row;
    Fc = S.fitPsychometric(GuessFromCatchTrials = true);
    results(end+1,:) = check('the catch false-alarm rate is the built-in fit''s guess rate', ...
        abs(C.CatchFalseAlarmRate - Fc.GuessRate) < 1e-12 && Fc.GuessRateSource == "catch");
    E = psychophysics.Staircase(Data([]), 'Depth').psychometricCounts();
    results(end+1,:) = check('no trials: empty counts and the reason', isempty(E.Levels) && E.Message ~= "");
catch ME
    results(end+1,:) = check(['group 4 threw: ' ME.message], false);
end

%% 5. fromCounts
try
    behavior.fit.Psignifit.clearCache();
    C = S.psychometricCounts();
    s = behavior.Settings(Fit = struct(Engine = "psignifit"), Psignifit = struct(Grid = "coarse"));
    [o, info] = s.psignifitOptions();
    F = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, o, info);
    data = [C.Levels' C.NumYes' C.NumTotal'];
    evalc('direct = psignifit(data, o);');
    results(end+1,:) = check('the common schema holds psignifit''s own numbers (Fit, interval, deviance)', ...
        F.Engine == "psignifit" && F.Converged && F.Identifiable && F.Threshold == direct.Fit(1) ...
        && F.CI.ThresholdLo == direct.conf_Intervals(1,1,1) && F.CI.ThresholdHi == direct.conf_Intervals(1,2,1) ...
        && F.Lambda == direct.Fit(3) && F.Gamma == direct.Fit(4) && F.Eta == direct.Fit(5) ...
        && F.Width == direct.Fit(2) && F.Deviance == direct.deviance && abs(F.Threshold - 20) < 3);
    results(end+1,:) = check('Raw is psignifit''s result without the two posterior grids, plus its input', ...
        ~isfield(F.Raw, 'Posterior') && ~isfield(F.Raw, 'weight') && isfield(F.Raw, 'marginals') ...
        && isequal(F.Raw.Input.data, data) && F.Raw.GammaSource == "estimated");
    results(end+1,:) = check('slope at the threshold is getSlope''s, the curve runs past the data', ...
        F.Beta == getSlope(direct, F.Threshold) && min(F.Curve.x) < min(C.Levels) && max(F.Curve.x) > max(C.Levels) ...
        && all(F.Curve.P >= 0 & F.Curve.P <= 1));

    sa = behavior.Settings(Fit = struct(Engine = "psignifit"), ...
        Psignifit = struct(Grid = "coarse", CriterionScale = "absolute", ThresholdPC = 0.75));
    [oa, ia] = sa.psignifitOptions();
    Fa = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, oa, ia);
    evalc('directA = psignifit(data, oa);');
    [thA, ciA] = getThreshold(directA, 0.75, false);
    results(end+1,:) = check('an absolute criterion is getThreshold at that proportion', ...
        Fa.Threshold == thA && Fa.CI.ThresholdLo == ciA(1,1) && Fa.Threshold > F.Threshold);

    sw = behavior.Settings(Fit = struct(Engine = "psignifit"), Psignifit = struct(Grid = "coarse", Sigmoid = "weibull"));
    [ow, iw] = sw.psignifitOptions();
    Fw = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, ow, iw);
    results(end+1,:) = check('a log-axis sigmoid reports its threshold in stimulus units', ...
        Fw.Identifiable && abs(Fw.Threshold - exp(Fw.Raw.Fit(1))) < 1e-12 && abs(Fw.Threshold - 20) < 4);

    F1 = behavior.fit.Psignifit.fromCounts([10 10], [3 4], [5 5], o, info);
    F2 = behavior.fit.Psignifit.fromCounts([-4 0 4], [1 3 5], [5 5 5], ow, iw);
    results(end+1,:) = check('refusals are messages, with the counts kept: one level; a log axis below zero', ...
        contains(F1.Message, "two distinct") && ~F1.Converged && isnan(F1.Threshold) ...
        && contains(F2.Message, "positive") && isequal(F2.Levels, [-4 0 4]));

    lv = 1:30;
    [printed, Fp] = localCapture(@() behavior.fit.Psignifit.fromCounts(lv, double(lv > 15) .* 3, ...
        repmat(3, 1, 30), o, info));
    [printedA, Fpa] = localCapture(@() behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, ...
        oa, ia, UseCache = false));
    results(end+1,:) = check('psignifit''s warnings (and getThreshold''s) are captured in Warnings, and nothing is printed', ...
        any(contains(Fp.Warnings, "pooled")) && ~any(contains(Fp.Warnings, ["> In" "[" "]"])) ...
        && any(contains(Fpa.Warnings, "upper bounds")) && ~contains(printed + printedA, "Warning"));

    Fe = behavior.fit.Psignifit.fromCounts(30:2:40, repmat(20, 1, 6), repmat(20, 1, 6), o, info);
    results(end+1,:) = check('a threshold below every level tested is kept and called an extrapolation', ...
        Fe.Identifiable && Fe.Threshold < 30 && any(contains(Fe.Warnings, "extrapolation")));
catch ME
    results(end+1,:) = check(['group 5 threw: ' ME.message], false);
end

%% 6. The cache
try
    t = tic;
    Fr = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, o, info);
    hit = toc(t);
    files = dir(fullfile(behavior.fit.Psignifit.cacheFolder(), 'fit_*.mat'));
    Fn = behavior.fit.Psignifit.fromCounts(C.Levels, C.NumYes, C.NumTotal, o, info, UseCache = false);
    results(end+1,:) = check(sprintf('a repeat is a cache hit (%.0f ms) and the same fit', 1000 * hit), ...
        isequaln(rmfield(Fr, 'Raw'), rmfield(F, 'Raw')) && hit < 0.2);
    results(end+1,:) = check('fits are cached on disk under the cache folder, never under a root', ...
        ~isempty(files) && startsWith(behavior.fit.Psignifit.cacheFolder(), behavior.Catalog.defaultCacheFolder()));
    results(end+1,:) = check('UseCache = false refits to the same numbers', ...
        Fn.Threshold == F.Threshold && Fn.Deviance == F.Deviance);
catch ME
    results(end+1,:) = check(['group 6 threw: ' ME.message], false);
end

%% 7. Session.analyze, Aggregate and the export
try
    s = behavior.Settings(Fit = struct(Engine = "psignifit"), Psignifit = struct(Grid = "coarse"));
    sess = behavior.Session.load(localFirstSession(root, cache), Root = root);
    R = sess.analyze(s);
    results(end+1,:) = check('analyze fits with psignifit: no fit_failed, a threshold near 20 dB', ...
        R.Fit.Engine == "psignifit" && ~any(R.QC == "fit_failed") && abs(R.Fit.Threshold - 20) < 3);
    T = behavior.Aggregate.thresholds({R});
    X = behavior.Export.tables(T, R, Tables = "fits").fits;
    results(end+1,:) = check('Aggregate carries the fit; the fits table has engine, width, eta, deviance, version', ...
        T.FitThreshold == R.Fit.Threshold && X.engine == "psignifit" && X.width == R.Fit.Width ...
        && X.eta == R.Fit.Eta && X.deviance == R.Fit.Deviance && X.guess_rate_source == "estimated" ...
        && X.engine_version == behavior.fit.Psignifit.version());
    Rb = sess.analyze(behavior.Settings());
    Xb = behavior.Export.tables(behavior.Aggregate.thresholds({Rb}), Rb, Tables = "fits").fits;
    results(end+1,:) = check('a built-in fit leaves width, eta and version empty and fills deviance', ...
        Xb.engine == "builtin" && isnan(Xb.width) && isnan(Xb.eta) && isfinite(Xb.deviance) && Xb.engine_version == "");
catch ME
    results(end+1,:) = check(['group 7 threw: ' ME.message], false);
end

%% 8. PsignifitPlot
try
    f = uifigure('Visible', 'off');
    g = uigridlayout(f, [1 6]);
    ax = gobjects(1, 6);
    for k = 1:6, ax(k) = uiaxes(g); end
    colormap(ax(6), cool(7));
    rngBefore = rng();
    other = figure('Visible', 'off');
    figsBefore = numel(findall(groot, 'Type', 'figure'));
    H = behavior.fit.PsignifitPlot.psych(ax(1), R.Fit, Unit = "dB", Parameter = "Depth");
    behavior.fit.PsignifitPlot.marginal(ax(2), R.Fit, "threshold", Unit = "dB");
    Hp = behavior.fit.PsignifitPlot.pair(ax(3), R.Fit, 1, 2);
    results(end+1,:) = check('plotPsych, plotMarginal and plot2D draw into uiaxes and leave no window behind', ...
        numel(findall(groot, 'Type', 'figure')) == figsBefore && ~isempty(H.Line) ...
        && ~isempty(findobj(ax(1), 'Tag', 'BehaviorPlot:PsignifitPsych')) ...
        && ~isempty(findobj(ax(2), 'Tag', 'BehaviorPlot:PsignifitMarginal')) && isscalar(Hp.Image) ...
        && ~isempty(ax(3).XLabel.String) && ~isempty(ax(3).YLabel.String));
    results(end+1,:) = check('the window is put back: hidden, handle hidden, current figure, figure colormap', ...
        f.Visible == "off" && f.HandleVisibility == "off" && isequal(get(groot, 'CurrentFigure'), other) ...
        && isequal(f.Colormap, parula(256)));
    results(end+1,:) = check('plot2D''s colormap is its axes'' alone: another axes keeps its own', ...
        size(ax(3).Colormap, 1) == 200 && size(ax(6).Colormap, 1) == 7);
    Rf = sess.analyze(behavior.Settings(Fit = struct(Engine = "psignifit"), ...
        Psignifit = struct(Grid = "coarse", EtaMode = "fixed", EtaValue = 0)));
    Hm = behavior.fit.PsignifitPlot.marginal(ax(4), Rf.Fit, 5);
    Hb = behavior.fit.PsignifitPlot.psych(ax(5), Rb.Fit);
    results(end+1,:) = check('a fixed parameter and a built-in fit draw their reason, not an error', ...
        contains(Hm.Message.String, "held fixed") && contains(Hb.Message.String, "not made by psignifit"));
    fb = behavior.fit.PsignifitPlot.bayes(R.Fit);
    fp = behavior.fit.PsignifitPlot.priors(R.Fit);
    fm = behavior.fit.PsignifitPlot.modelChecks(R.Fit);
    results(end+1,:) = check('plotBayes, plotPrior and plotsModelfit open windows of their own', ...
        numel(findall(fb, 'Type', 'axes')) >= 6 && numel(findall(fp, 'Type', 'axes')) == 6 && numel(fm) == 2 ...
        && all(string({fm.Tag}) == "BehaviorPlot:PsignifitWindow"));
    results(end+1,:) = check('looking at a fit leaves the global random stream as it was', isequal(rng(), rngBefore));
    delete([fb fp fm(:)' other]);
    delete(f);
catch ME
    results(end+1,:) = check(['group 8 threw: ' ME.message], false);
end

%% 9. The Settings dialog's psignifit page
try
    st = behavior.Study(root, Store = string(store), Roster = "none", CacheFolder = string(cache));
    D = gui.behavior.SettingsDialog(st, Visible = false, Section = "psignifit");
    results(end+1,:) = check('Section = "psignifit" opens on the psignifit page, which says where psignifit is', ...
        string(D.H.tabs.SelectedTab.Title) == "psignifit" && contains(D.H.psState.Text, "installed") ...
        && contains(D.H.psDetail.Text, behavior.fit.Psignifit.locate().Folder) && D.H.psDirections.Visible == "off");
    D.setPsignifitEngine(true);
    c = D.control("Psignifit", "ExpType"); c.Value = 'nAFC';
    c = D.control("Psignifit", "Grid"); c.Value = 'coarse';
    c = D.control("Psignifit", "StimulusRange"); c.Value = '0 60';
    D.check();
    results(end+1,:) = check('the switch is Fit.Engine; nAFC lights ExpN and greys the guess-rate mode', ...
        string(D.control("Fit", "Engine").Value) == "psignifit" && D.H.psEngine.Value ...
        && D.control("Psignifit", "ExpN").Enable == "on" && D.control("Psignifit", "GammaMode").Enable == "off");
    c = D.control("Psignifit", "ExpType"); c.Value = 'YesNo';
    D.check();
    ok = D.apply();
    st.save();
    J = jsondecode(fileread(fullfile(store, 'project.json')));
    results(end+1,:) = check('Apply makes them the study''s, and the project file holds them', ...
        ok && st.Settings.Fit.Engine == "psignifit" && st.Settings.Psignifit.Grid == "coarse" ...
        && string(J.Settings.Fit.Engine) == "psignifit" && string(J.Settings.Psignifit.Grid) == "coarse" ...
        && isequal(J.Settings.Psignifit.StimulusRange(:)', [0 60]));
    reopened = behavior.Project.open(string(root), Store = string(store));
    results(end+1,:) = check('reopened, the project''s settings are the same settings', ...
        reopened.Settings.hash() == st.Settings.hash());
    behavior.fit.Psignifit.override("missing");
    D.recheckPsignifit();
    results(end+1,:) = check('missing: the page shows the directions and Apply is greyed with the reason', ...
        contains(D.H.psState.Text, "not installed") && D.H.psDirections.Visible == "on" ...
        && any(contains(string(D.H.psDirections.Value), behavior.fit.Psignifit.URL)) ...
        && D.H.btnApply.Enable == "off" && any(startsWith(D.Problems, "psignifit: ")));
    behavior.fit.Psignifit.override("");
    bad = fullfile(tempdir, sprintf('not_psignifit_%d', pid));
    mkdir(bad);
    D.locatePsignifit(string(bad));
    rmdir(bad);
    results(end+1,:) = check('Locate Folder on a folder without psignifit reports it and changes nothing', ...
        contains(D.H.status.Text, "does not hold") && behavior.fit.Psignifit.available() ...
        && ispref('EPsych', 'PsignifitPath') == hadPsPref && D.H.btnApply.Enable == "on");
    delete(D);
    delete(st);
catch ME
    results(end+1,:) = check(['group 9 threw: ' ME.message], false);
end

%% 10. The Fit tab, the Session tab, and a generated script
try
    app = epsych.BehaviorAnalysis(root, Visible = false, Store = string(store), Roster = "none", ...
        CacheFolder = string(cache));
    S = app.Study;
    results(end+1,:) = check('the window has a Fit tab, fifth, and the project''s psignifit settings', ...
        app.TAB_NAMES(5) == "Fit" && isfield(app.Views, 'Fit') && S.Settings.Fit.Engine == "psignifit");
    keys = S.visibleKeys();
    app.showTab("Fit");
    app.selectSession(keys(1));
    V = app.Views.Fit;
    R = S.result(keys(1));
    results(end+1,:) = check('the Fit tab draws psignifit''s plotPsych and every free marginal', ...
        V.Key == keys(1) && ~isempty(findobj(V.H.psychAxes, 'Tag', 'BehaviorPlot:PsignifitPsych')) ...
        && all(arrayfun(@(a) ~isempty(findobj(a, 'Tag', 'BehaviorPlot:PsignifitMarginal')), V.H.marginalAxes([1 2 3 5]))) ...
        && V.H.root.RowHeight{2} > 0 && V.H.btnBayes.Enable == "on");
    D = V.H.table.Data;
    results(end+1,:) = check('its table lists the five parameters with intervals, the slope and the deviance', ...
        size(D, 1) >= 9 && startsWith(string(D{1, 1}), "Threshold") && string(D{1, 2}) == sprintf('%.4g', R.Fit.Threshold) ...
        && any(string(D(:, 1)) == "Deviance") && any(string(D(:, 1)) == "Slope at threshold"));
    V.H.chkPair.Value = true;
    V.H.ddPairY.Value = 'threshold';
    V.H.ddPairX.Value = 'lambda';
    feval(V.H.ddPairX.ValueChangedFcn, V.H.ddPairX, []);
    results(end+1,:) = check('ticking Joint posterior draws plot2D of the chosen pair', ...
        isscalar(findobj(V.H.pairAxes, 'Type', 'image')));
    openItem = @(ax) findobj(ax.ContextMenu, 'Tag', 'BehaviorView:OpenInFigure');
    results(end+1,:) = check('every Fit-tab plot keeps Open in New Figure through psignifit''s axes reset', ...
        all(arrayfun(@(a) isscalar(openItem(a)), [V.H.psychAxes V.H.marginalAxes V.H.pairAxes])) ...
        && all(ismember(["psych" "marginal1" "marginal5" "pair"], [V.plots.Key])));
    fp = V.openInFigure("psych", Visible = false);
    fm = V.openInFigure("marginal1", Visible = false);
    fj = V.openInFigure("pair", Visible = false);
    results(end+1,:) = check('plotPsych, a marginal and the joint posterior each open in a figure of their own', ...
        ~isempty(findobj(fp, 'Tag', 'BehaviorPlot:PsignifitPsych')) ...
        && ~isempty(findobj(fm, 'Tag', 'BehaviorPlot:PsignifitMarginal')) ...
        && isscalar(findobj(fj, 'Type', 'image')) && contains(string(fm.Name), "Threshold"));
    delete([fp fm fj]);
    SV = app.Views.Session;
    results(end+1,:) = check('the Session tab''s fit panel is psignifit''s plot too', ...
        ~isempty(findobj(SV.H.fitAxes, 'Tag', 'BehaviorPlot:PsignifitPsych')) ...
        && any(contains(SV.H.summary.Value, "psignifit")));
    file = fullfile(out, 'psignifit_fit.png');
    app.exportFigure(file);
    results(end+1,:) = check('Export Figure on the Fit tab writes the psychometric plot', isfile(file));

    scriptFile = app.writeScript(fullfile(out, 'replicate_psignifit.m'), Scope = "session");
    code = string(fileread(scriptFile));
    txt = localRunScript(scriptFile, root, out);
    results(end+1,:) = check('the script names psignifit''s folder and commit, and replicates the fit exactly', ...
        contains(code, "PSIGNIFITROOT") && contains(code, "psignifit") ...
        && contains(code, "behavior.fit.PsignifitPlot.psych") && contains(txt, "replicated exactly") ...
        && ~contains(txt, "differ"));

    s = S.Settings;
    s.Fit = struct(Engine = "builtin");
    app.applySettings(s);
    results(end+1,:) = check('the built-in engine: no posterior row, a pointer to psignifit, no psignifit plot', ...
        V.H.root.RowHeight{2} == 0 && contains(V.H.hint.Text, "psignifit") ...
        && isempty(findobj(V.H.psychAxes, 'Tag', 'BehaviorPlot:PsignifitPsych')) && V.H.btnBayes.Enable == "off");
    delete(app);
    results(end+1,:) = check('deleting the window leaves no Behavior Analysis figure', ...
        isempty(findall(groot, 'Type', 'figure', 'Tag', epsych.BehaviorAnalysis.FIGURE_TAG)));
catch ME
    results(end+1,:) = check(['group 10 threw: ' ME.message], false);
end
end

localReport(results);
delete(noOverride);
delete(closeWindows);
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
fprintf('smoke_test_behavior_psignifit: %d checks, %d failed\n', size(results, 1), nFail);
if nFail > 0
    error('smoke_test_behavior_psignifit:Failed', '%d check(s) failed', nFail);
end
end

function [row, C] = localCountsCheck(S, includeAborts)
% psychometricCounts against the counts fitPsychometric fitted.
C = S.psychometricCounts(IncludeAborts = includeAborts);
Fb = S.fitPsychometric(IncludeAborts = includeAborts);
row = check(sprintf('counts = the built-in fit''s counts (IncludeAborts=%d)', includeAborts), ...
    isequal(C.Levels, Fb.Levels) && isequal(C.NumYes, Fb.NumYes) && isequal(C.NumTotal, Fb.NumTotal) ...
    && C.NumScored == Fb.NumScored && C.NumAborted == Fb.NumAborted && C.Message == "");
end

function [txt, out] = localCapture(fcn)
% What a call printed, and what it returned.
assert(isa(fcn, 'function_handle'));
out = [];
txt = string(evalc('out = fcn();'));
end

function id = localThrows(fcn)
id = "";
try
    fcn();
catch ME
    id = string(ME.identifier);
end
end

function row = localFirstSession(root, cache)
c = behavior.Catalog(root, CacheFolder = string(cache));
c.scan();
row = c.Sessions(1, :);
end

function txt = localRunScript(file, root, out)
% Run a generated script in a workspace of its own, ROOT and OUTFOLDER set,
% closing any figure it opens.
ROOT = string(root);
OUTFOLDER = string(out);
figsBefore = findall(groot, 'Type', 'figure');
txt = evalc(sprintf('run(''%s'')', char(file)));
figsAfter = findall(groot, 'Type', 'figure');
delete(figsAfter(arrayfun(@(f) ~any(figsBefore == f), figsAfter)));
assert(ROOT ~= "" && OUTFOLDER ~= "");
end

function s = localSavePrefs(group)
s = struct('group', group, 'existed', ispref(group), 'values', struct());
if s.existed
    s.values = getpref(group);
end
end

function localRestorePrefs(saved, hadPsPref, psPref)
for k = 1:numel(saved)
    s = saved{k};
    try
        if ispref(s.group), rmpref(s.group); end
        names = fieldnames(s.values);
        for j = 1:numel(names)
            setpref(s.group, names{j}, s.values.(names{j}));
        end
    catch
    end
end
try
    if hadPsPref
        setpref('EPsych', 'PsignifitPath', psPref);
    elseif ispref('EPsych', 'PsignifitPath')
        rmpref('EPsych', 'PsignifitPath');
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
for tag = {'EPsychBehaviorSettings', 'BehaviorPlot:PsignifitWindow'}
    delete(findall(groot, 'Type', 'figure', 'Tag', tag{1}));
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
