function smoke_test_behavior_plot()
% smoke_test_behavior_plot
% Standing proof of behavior.Plot, the offline analysis figures: every
% figure is drawn into a hidden uifigure's uiaxes AND a hidden classic
% figure's axes, and checked for the tagged graphics it promises, its axis
% labels, colours that stay with a facet level from one figure to the next,
% "No data" instead of an error for an empty or all-NaN input, and that it
% never makes a figure of its own.
%
% Fixture: as tmp/smoke_test_behavior_study.m -- two subjects, three "Pre"
% sessions (threshold 20) and three "Post" (threshold 26) each, saved as
% Data-only files. Data-only files carry no snapshot, so the results are
% given Unit "dB" by hand: that is what a session with a snapshot reports.
%
%   run('tmp/smoke_test_behavior_plot.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('behavior.Plot', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);

pid = feature('getpid');
root = fullfile(tempdir, sprintf('epsych_behavior_plot_smoke_%d', pid));
cache = fullfile(tempdir, sprintf('epsych_behavior_plot_cache_%d', pid));
if isfolder(root), rmdir(root, 's'); end
mkdir(root);
figsBefore = findall(groot, 'Type', 'figure');
uf = uifigure('Visible', 'off', 'Position', [100 100 900 600]);
gl = uigridlayout(uf, [1 1]);
uax = uiaxes(gl);
uax.Tag = 'MyAxes';
cf = figure('Visible', 'off', 'Position', [100 100 900 600]);
cax = axes(cf);
cleanup = onCleanup(@() localCleanup(root, cache, [uf cf]));

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
    R{i}.Unit = "dB";
end
Rs = [R{:}];
T = behavior.Aggregate.thresholds(R, cat.Sessions);
fTag = behavior.Facet("tag", Index = 1);
fSubj = behavior.Facet("subject");
E = behavior.Aggregate.thresholds({});
Tnan = T;
Tnan.Threshold(:) = NaN;
Tnan.FitThreshold(:) = NaN;
Tnan.DPrime(:) = NaN;

%% 1. palette and colorsFor
try
    P = behavior.Plot.palette(8);
    outcome = localHex(epsych.BitMask.getDefaultColors([epsych.BitMask.Undefined epsych.BitMask.Hit ...
        epsych.BitMask.Miss epsych.BitMask.CorrectReject epsych.BitMask.FalseAlarm epsych.BitMask.Abort]));
    d = min(pdist2(P, outcome), [], 'all');
    results(end+1,:) = check('palette(8): 8 distinct RGB rows in 0..1', ...
        isequal(size(P), [8 3]) && size(unique(P, 'rows'), 1) == 8 && all(P(:) >= 0 & P(:) <= 1));
    results(end+1,:) = check(sprintf('no palette hue is an outcome colour (nearest %.2f)', d), d > 0.25);
    P30 = behavior.Plot.palette(30);
    results(end+1,:) = check('palette(30) keeps 24+ distinct rows and repeats nothing among the first 24', ...
        size(unique(round(P30(1:24, :), 6), 'rows'), 1) == 24 && isequal(P30(1:8, :), P));
    results(end+1,:) = check('palette(0) is 0-by-3', isequal(size(behavior.Plot.palette(0)), [0 3]));
    [c, lev, idx] = behavior.Plot.colorsFor(fSubj, T);
    results(end+1,:) = check('colorsFor: a colour per level in the facet''s order', ...
        isequal(lev, ["S1"; "S2"]) && isequal(c, P(1:2, :)) && isequal(idx, double(T.Subject == "S2") + 1));
catch ME
    results(end+1,:) = check(['group 1: ' ME.message], false);
end

results = [results; localPerAxes(uax, "uiaxes", T, Tnan, E, R, Rs, cat, fTag)];
results = [results; localPerAxes(cax, "axes", T, Tnan, E, R, Rs, cat, fTag)];

%% 9. Contract
try
    results(end+1,:) = check('a non-axes is refused', ...
        throwsWith(@() behavior.Plot.thresholdTimeline(uf, T), 'behavior:Plot:InvalidAxes'));
    figsAfter = findall(groot, 'Type', 'figure');
    results(end+1,:) = check('no figure was created besides the two the test made', ...
        numel(figsAfter) == numel(figsBefore) + 2);
    behavior.Plot.groupComparison(uax, T, "Threshold", GroupBy = fTag);
    untagged = findall(uax.Children, 'flat', 'Tag', '');
    results(end+1,:) = check('every object drawn carries a BehaviorPlot tag', isempty(untagged) ...
        && all(startsWith(string(get(uax.Children, 'Tag')), "BehaviorPlot:")));
catch ME
    results(end+1,:) = check(['group 9: ' ME.message], false);
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
fprintf('smoke_test_behavior_plot: %d checks, %d failed\n', size(results, 1), nFail);
clear cleanup
if nFail > 0
    error('smoke_test_behavior_plot:Failed', '%d check(s) failed', nFail);
end
end


function results = localPerAxes(ax, nm, T, Tnan, E, R, Rs, cat, fTag)
% Groups 2-8: every figure drawn into one axes (a uiaxes or a classic one).
results = cell(0, 2);
colTimeline = [];

%% 2. thresholdTimeline
try
    H = behavior.Plot.thresholdTimeline(ax, T);
    pts = localTagged(ax, "Point");
    results(end+1,:) = check(nm + ": timeline draws one marker per session, a line per subject", ...
        localCount(pts) == 12 && numel(localTagged(ax, "SubjectLine")) == 2 && numel(pts) == 2);
    results(end+1,:) = check(nm + ": timeline handles are the tagged ones", ...
        isempty(setxor(H.Point(:), pts(:))) && isequal(H.Axes, ax));
    results(end+1,:) = check(nm + ": fitted thresholds as hollow markers, one per finite fit", ...
        localCount(localTagged(ax, "Fit")) == sum(isfinite(T.FitThreshold)) ...
        && all(strcmp({localTagged(ax, "Fit").MarkerFaceColor}, 'none')));
    results(end+1,:) = check(nm + ": ylabel names the value and its unit; xlabel the time axis", ...
        contains(ax.YLabel.String, "Reversal threshold") && contains(ax.YLabel.String, "dB") ...
        && contains(ax.XLabel.String, "date"));
    results(end+1,:) = check(nm + ": the legend names the levels with their n", ...
        isgraphics(H.Legend) && any(contains(H.Legend.String, "S1 (n=6)")) && H.Legend.Title.String == "Subject");
    results(end+1,:) = check(nm + ": the axes keeps its own Tag through the clear", ...
        nm == "axes" || strcmp(ax.Tag, 'MyAxes'));
    colTimeline = localColorOf(pts, "S1");

    Tq = T;
    Tq.NumQC(:) = 0;
    Tq.NumQC([2 5]) = 1;
    Tq.Threshold(3) = NaN;
    behavior.Plot.thresholdTimeline(ax, Tq, XAxis = "session", ShowFit = false);
    results(end+1,:) = check(nm + ": QC sessions ringed; a NaN skipped, not drawn at zero", ...
        localCount(localTagged(ax, "QC")) == 2 && localCount(localTagged(ax, "Point")) == 11 ...
        && isempty(localTagged(ax, "Fit")) && ~any(localYData(localTagged(ax, "Point")) == 0));
    results(end+1,:) = check(nm + ": XAxis session counts sessions", ...
        contains(ax.XLabel.String, "Session number") && max(localXData(localTagged(ax, "Point"))) == 6);
    behavior.Plot.thresholdTimeline(ax, T, XAxis = "days", ShowQC = false);
    results(end+1,:) = check(nm + ": XAxis days starts at 0", ...
        min(localXData(localTagged(ax, "Point"))) == 0 && contains(ax.XLabel.String, "Days"));
    H = behavior.Plot.thresholdTimeline(ax, E);
    results(end+1,:) = check(nm + ": an empty table draws No data", localIsNoData(ax, H));
    H = behavior.Plot.thresholdTimeline(ax, table());
    results(end+1,:) = check(nm + ": a table with no columns draws No data", localIsNoData(ax, H));
    H = behavior.Plot.thresholdTimeline(ax, Tnan);
    results(end+1,:) = check(nm + ": an all-NaN column draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 2: " + ME.message, false);
end

%% 3. metricTimeline
try
    behavior.Plot.metricTimeline(ax, T, "DPrime", ColorBy = fTag, XAxis = "session");
    pts = localTagged(ax, "Point");
    results(end+1,:) = check(nm + ": metric timeline colours by tag and labels d'", ...
        numel(pts) == 2 && localCount(pts) == sum(isfinite(T.DPrime)) && contains(ax.YLabel.String, "d'") ...
        && isempty(localTagged(ax, "Fit")) && isempty(localTagged(ax, "QC")));
    behavior.Plot.metricTimeline(ax, T, "AbortRate");
    results(end+1,:) = check(nm + ": a rate is labelled as a proportion", contains(ax.YLabel.String, "proportion"));
    H = behavior.Plot.metricTimeline(ax, Tnan, "DPrime");
    results(end+1,:) = check(nm + ": an all-NaN metric draws No data", localIsNoData(ax, H));
    results(end+1,:) = check(nm + ": an unknown column is refused", ...
        throwsWith(@() behavior.Plot.metricTimeline(ax, T, "Banana"), 'behavior:Plot:UnknownColumn'));
catch ME
    results(end+1,:) = check(nm + ": group 3: " + ME.message, false);
end

%% 4. groupComparison
try
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag);
    results(end+1,:) = check(nm + ": box: one box per level, 12 points, a median per subject x level", ...
        numel(localTagged(ax, "Box")) == 2 && localCount(localTagged(ax, "Point")) == 12 ...
        && numel(localTagged(ax, "SubjectMedian")) == 4 && numel(H.SubjectMedian) == 4);
    [levels, ~] = fTag.order(T);
    results(end+1,:) = check(nm + ": levels in facet order, n in the tick labels", ...
        isequal(numel(ax.XTick), 2) && startsWith(string(ax.XTickLabel{1}), levels(1)) ...
        && all(contains(string(ax.XTickLabel), "n=6")) && ax.XLabel.String == "Tag 1");
    results(end+1,:) = check(nm + ": ylabel names the value and its unit", ...
        contains(ax.YLabel.String, "Reversal threshold (dB)"));
    colCompare = localColorOf(localTagged(ax, "Point"), "S1");
    results(end+1,:) = check(nm + ": S1 keeps its colour from the timeline to the comparison", ...
        isequal(colTimeline, colCompare) && isequal(colCompare, behavior.Plot.palette(1)));
    boxTags = localTagSet(ax);

    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "bar");
    barTags = localTagSet(ax);
    eb = localTagged(ax, "ErrorBar");
    results(end+1,:) = check(nm + ": bar: a bar per level with a mean +/- SEM error bar", ...
        numel(localTagged(ax, "Bar")) == 2 && isscalar(eb) && numel(eb.XData) == 2 && isempty(localTagged(ax, "Box")));
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "bar", ShowCI = true);
    ci = localTagged(ax, "CI");
    results(end+1,:) = check(nm + ": bar with ShowCI draws the bootstrap CI from Stats.describe", ...
        isscalar(ci) && isempty(localTagged(ax, "ErrorBar")) && istable(H.Stats) ...
        && all(abs(ci.YData(:) - H.Stats.Mean(:)) < 1e-12) && all(isfinite(H.Stats.CILo)));

    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "strip", ShowSubjectMedians = false);
    stripTags = localTagSet(ax);
    results(end+1,:) = check(nm + ": strip: points and a mean line per level, nothing else", ...
        numel(localTagged(ax, "Mean")) == 2 && localCount(localTagged(ax, "Point")) == 12 ...
        && isempty(localTagged(ax, "Box")) && isempty(localTagged(ax, "Bar")) && isempty(localTagged(ax, "SubjectMedian")));
    results(end+1,:) = check(nm + ": the three kinds differ in what they draw", ...
        ~isequal(boxTags, barTags) && ~isequal(barTags, stripTags) && ~isequal(boxTags, stripTags));

    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, ColorBy = fTag, ShowPoints = false);
    b = localTagged(ax, "Box");
    results(end+1,:) = check(nm + ": coloured by its own facet, the boxes take the level colours; no points", ...
        isempty(localTagged(ax, "Point")) && numel(b) == 2 ...
        && ismember(behavior.Plot.palette(1), vertcat(b.BoxFaceColor), 'rows'));
    behavior.Plot.groupComparison(ax, T, "Threshold");
    results(end+1,:) = check(nm + ": no facet: one box, a median per subject", ...
        isscalar(localTagged(ax, "Box")) && numel(localTagged(ax, "SubjectMedian")) == 2);
    H = behavior.Plot.groupComparison(ax, E, "Threshold");
    results(end+1,:) = check(nm + ": comparison of an empty table draws No data", localIsNoData(ax, H));
    H = behavior.Plot.groupComparison(ax, Tnan, "Threshold", GroupBy = fTag, Kind = "bar");
    results(end+1,:) = check(nm + ": comparison of an all-NaN column draws No data", localIsNoData(ax, H));

    % Mean and spread: what Spread names is what is drawn, about the mean
    % (sem, sd, ci) or the median (iqr, range); ShowMean takes the mean away.
    D4 = behavior.Stats.describe(T, "Threshold", GroupBy = fTag);
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag);
    mn = localTagged(ax, "Mean");
    results(end+1,:) = check(nm + ": box by default: a mean square beside each box, no spread", ...
        isscalar(mn) && max(abs(mn.XData(:) - [1.36; 2.36])) < 1e-12 && max(abs(mn.YData(:) - D4.Mean)) < 1e-12 ...
        && isempty(localTagged(ax, "ErrorBar")) && isempty(localTagged(ax, "CI")) && H.SpreadKind == "none");
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, ShowMean = false);
    results(end+1,:) = check(nm + ": box with ShowMean false and no spread: no mean, no Stats needed", ...
        isempty(localTagged(ax, "Mean")) && isempty(H.Stats) && numel(localTagged(ax, "Box")) == 2);
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "strip", Spread = "sd");
    eb = localTagged(ax, "ErrorBar");
    results(end+1,:) = check(nm + ": strip Spread sd: mean +/- SD bars, tagged ErrorBar, named in the legend", ...
        isscalar(eb) && eb.UserData.Spread == "sd" && max(abs(eb.YData(:) - D4.Mean)) < 1e-12 ...
        && max(abs(eb.YPositiveDelta(:) - D4.SD)) < 1e-12 && H.Spread == eb ...
        && any(contains(H.Legend.String, "SD")) && any(strcmp(H.Legend.String, 'Mean')));
    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "bar", Spread = "iqr");
    eb = localTagged(ax, "ErrorBar");
    results(end+1,:) = check(nm + ": bar Spread iqr: bars from Q1 to Q3 through the median", ...
        isscalar(eb) && max(abs(eb.YData(:) - D4.Median)) < 1e-12 ...
        && max(abs(eb.YData(:) - eb.YNegativeDelta(:) - D4.Q1)) < 1e-12 ...
        && max(abs(eb.YData(:) + eb.YPositiveDelta(:) - D4.Q3)) < 1e-12 && numel(localTagged(ax, "Bar")) == 2);
    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "bar", Spread = "range", ShowMean = false);
    eb = localTagged(ax, "ErrorBar");
    results(end+1,:) = check(nm + ": bar Spread range, ShowMean false: min-to-max bars and no bars", ...
        isscalar(eb) && max(abs(eb.YData(:) - eb.YNegativeDelta(:) - D4.Min)) < 1e-12 ...
        && max(abs(eb.YData(:) + eb.YPositiveDelta(:) - D4.Max)) < 1e-12 && isempty(localTagged(ax, "Bar")));
    H = behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Spread = "ci", NumBoot = 200);
    ci = localTagged(ax, "CI");
    results(end+1,:) = check(nm + ": Spread ci draws the bootstrap CI beside a box without ShowCI", ...
        isscalar(ci) && max(abs(ci.XData(:) - [1.36; 2.36])) < 1e-12 && all(isfinite(H.Stats.CILo)) ...
        && H.Stats.Properties.UserData.NumBoot == 200 && H.SpreadKind == "ci");
    behavior.Plot.groupComparison(ax, T, "Threshold", GroupBy = fTag, Kind = "strip", ShowMean = false, Spread = "none");
    results(end+1,:) = check(nm + ": strip with no mean and no spread is points alone", ...
        isempty(localTagged(ax, "Mean")) && isempty(localTagged(ax, "ErrorBar")) ...
        && localCount(localTagged(ax, "Point")) == 12);
    results(end+1,:) = check(nm + ": resolveSpread: auto is none beside a box, SEM elsewhere, the CI with ShowCI", ...
        behavior.Plot.resolveSpread("auto", Kind = "box") == "none" ...
        && behavior.Plot.resolveSpread("auto", Kind = "strip") == "sem" ...
        && behavior.Plot.resolveSpread("auto", Kind = "lines", ShowCI = true) == "ci" ...
        && behavior.Plot.resolveSpread("iqr", Kind = "box", ShowCI = true) == "iqr");
    results(end+1,:) = check(nm + ": an unknown spread is refused", ...
        throwsWith(@() behavior.Plot.groupComparison(ax, T, "Threshold", Spread = "banana"), 'behavior:Plot:UnknownSpread'));

    % The threshold both ways, and the psignifit parameters, as values.
    behavior.Plot.groupComparison(ax, T, "WeightedMedianBlockThreshold", GroupBy = fTag);
    results(end+1,:) = check(nm + ": a weighted block threshold is compared, labelled with its unit", ...
        localCount(localTagged(ax, "Point")) == sum(isfinite(T.WeightedMedianBlockThreshold)) ...
        && contains(ax.YLabel.String, "Median block threshold, weighted (dB)"));
    Tw = T;
    Tw.FitWidth = 2 + (1:height(Tw))' / 10;
    Tw.FitShape(:) = "weibull";
    behavior.Plot.groupComparison(ax, Tw, "FitWidth", GroupBy = fTag);
    yLog = string(ax.YLabel.String);
    Tw.FitShape(:) = "norm";
    behavior.Plot.groupComparison(ax, Tw, "FitWidth", GroupBy = fTag);
    results(end+1,:) = check(nm + ": a psignifit width is in log units for weibull, the parameter's otherwise", ...
        contains(yLog, "Fitted width (log units)") && contains(ax.YLabel.String, "Fitted width (dB)"));
catch ME
    results(end+1,:) = check(nm + ": group 4: " + ME.message, false);
end

%% 5. subjectLines
try
    H = behavior.Plot.subjectLines(ax, T, "Threshold");
    sl = localTagged(ax, "SubjectLine");
    mn = localTagged(ax, "Mean");
    results(end+1,:) = check(nm + ": a line per subject through its two level medians", ...
        numel(sl) == 2 && all(arrayfun(@(h) numel(h.XData), sl) == 2) && numel(H.SubjectLine) == 2);
    S = behavior.Aggregate.bySubject(T, "Threshold", GroupBy = fTag);
    s1 = H.SubjectLine(arrayfun(@(h) h.UserData.Subject == "S1", H.SubjectLine));
    [levels, ~] = fTag.order(T);
    expect = arrayfun(@(L) S.Median(S.Subject == "S1" & S.Level == L), levels);
    results(end+1,:) = check(nm + ": the line goes through the subject''s medians in level order", ...
        isequal(s1.XData(:), [1; 2]) && max(abs(s1.YData(:) - expect)) < 1e-12);
    results(end+1,:) = check(nm + ": the group mean of subject medians as a heavier line", ...
        isscalar(mn) && numel(mn.YData) == 2 && mn.LineWidth > s1.LineWidth ...
        && abs(mn.YData(1) - mean(S.Median(S.Level == levels(1)))) < 1e-12);
    results(end+1,:) = check(nm + ": ticks name the levels with n subjects; S1 in its subject colour", ...
        all(contains(string(ax.XTickLabel), "n=2")) && isequal(s1.Color, behavior.Plot.palette(1)));
    H = behavior.Plot.subjectLines(ax, Tnan, "Threshold");
    results(end+1,:) = check(nm + ": subject lines of an all-NaN column draw No data", localIsNoData(ax, H));
    H = behavior.Plot.subjectLines(ax, E, "Threshold");
    results(end+1,:) = check(nm + ": subject lines of an empty table draw No data", localIsNoData(ax, H));

    H = behavior.Plot.subjectLines(ax, T, "Threshold");
    eb = localTagged(ax, "ErrorBar");
    results(end+1,:) = check(nm + ": subject lines: the mean line and a SEM of the subject medians by default", ...
        isscalar(eb) && eb.UserData.Spread == "sem" && H.SpreadKind == "sem" ...
        && max(abs(eb.YPositiveDelta(:) - H.Stats.SEM)) < 1e-12 ...
        && any(contains(H.Legend.String, "Mean of subject medians")));
    H = behavior.Plot.subjectLines(ax, T, "Threshold", Spread = "range");
    eb = localTagged(ax, "ErrorBar");
    results(end+1,:) = check(nm + ": subject lines Spread range: min to max of the subject medians", ...
        isscalar(eb) && max(abs(eb.YData(:) - H.Stats.Median)) < 1e-12 ...
        && max(abs(eb.YData(:) + eb.YPositiveDelta(:) - H.Stats.Max)) < 1e-12);
    H = behavior.Plot.subjectLines(ax, T, "Threshold", ShowMean = false, Spread = "none");
    results(end+1,:) = check(nm + ": subject lines with neither: the subjects alone", ...
        isempty(localTagged(ax, "Mean")) && isempty(localTagged(ax, "ErrorBar")) ...
        && numel(H.SubjectLine) == 2 && istable(H.Stats));
catch ME
    results(end+1,:) = check(nm + ": group 5: " + ME.message, false);
end

%% 6. staircaseOverlay
try
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions);
    tr = localTagged(ax, "Track");
    results(end+1,:) = check(nm + ": overlay: one track per result", numel(tr) == 12 && numel(H.Track) == 12);
    okLen = arrayfun(@(r) numel(r.Track.Value), Rs);
    lens = arrayfun(@(h) numel(h.XData), H.Track);
    results(end+1,:) = check(nm + ": each track has its result''s stimulus trials", isequal(lens(:), okLen(:)));
    results(end+1,:) = check(nm + ": thresholds as end markers, none for reversals unless asked", ...
        numel(localTagged(ax, "Threshold")) == sum(isfinite([Rs.Threshold])) && isempty(localTagged(ax, "Reversal")) ...
        && all(strcmp({localTagged(ax, "Threshold").LineStyle}, 'none')) ...
        && all(arrayfun(@(h) isscalar(h.XData), localTagged(ax, "Threshold"))));
    results(end+1,:) = check(nm + ": overlay ylabel is the parameter and unit; a legend entry per level and the threshold key", ...
        contains(ax.YLabel.String, "Depth (dB)") && numel(H.Legend.String) == 3 ...
        && any(contains(H.Legend.String, "S1 (n=6)")) && any(startsWith(H.Legend.String, "Session threshold")));
    results(end+1,:) = check(nm + ": tracks are steps by default, plain lines with Steps=false", ...
        all(strcmp(get(H.Track, 'Type'), 'stair')) && H.ColorMap == "categorical" && isempty(H.ColorBar));
    s1 = H.Track(arrayfun(@(h) contains(h.UserData.Key, "/S1/"), H.Track));
    results(end+1,:) = check(nm + ": S1''s tracks share the colour S1 has everywhere else", ...
        numel(s1) == 6 && all(arrayfun(@(h) isequal(h.Color, behavior.Plot.palette(1)), s1)));

    H = behavior.Plot.staircaseOverlay(ax, R, cat.Sessions, Normalize = "fraction", ShowReversals = true, ...
        ColorBy = fTag);
    results(end+1,:) = check(nm + ": fraction: every track ends at x = 1 and starts above 0", ...
        all(arrayfun(@(h) h.XData(end) == 1 && h.XData(1) > 0, H.Track)));
    results(end+1,:) = check(nm + ": reversals marked when asked, one marker set per track", ...
        numel(localTagged(ax, "Reversal")) == sum(arrayfun(@(r) any(r.Track.Reversal), Rs)));
    results(end+1,:) = check(nm + ": coloured by tag: two colours, legend says the levels", ...
        size(unique(vertcat(H.Track.Color), 'rows'), 1) == 2 ...
        && isempty(setxor(["Pre (n=6)" "Post (n=6)" "Session threshold (n=12)" "Reversal"], string(H.Legend.String))));
    H = behavior.Plot.staircaseOverlay(ax, Rs, [], Normalize = "trial", ShowThresholds = false, Steps = false);
    results(end+1,:) = check(nm + ": no sessions table: still a track each, renumbered from 1", ...
        numel(H.Track) == 12 && all(arrayfun(@(h) h.XData(1) == 1, H.Track)) && isempty(H.Threshold) ...
        && all(strcmp(get(H.Track, 'Type'), 'line')));

    % Colour mapping across an ordered facet.
    fSess = behavior.Facet("session");
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorBy = fSess);
    c6 = behavior.Plot.sequential("parula", 6);
    ord = arrayfun(@(h) h.UserData.Level, H.Track);
    results(end+1,:) = check(nm + ": auto + session: a parula gradient, level k = sample k, drawn in level order", ...
        H.ColorMap == "parula" && all(arrayfun(@(h) isequal(h.Color, c6(h.UserData.Level, :)), H.Track)) ...
        && issorted(ord) && size(unique(vertcat(H.Track.Color), 'rows'), 1) == 6);
    results(end+1,:) = check(nm + ": six gradient levels fit the legend, so no colour bar", ...
        isempty(H.ColorBar) && numel(H.Legend.String) == 7);
    S12 = cat.Sessions;
    S12.Group_Run = compose("R%02d", (1:height(S12))');
    H = behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Run"), ...
        ColorMap = "turbo");
    results(end+1,:) = check(nm + ": a gradient over 12 levels is keyed by a colour bar, not 12 legend rows", ...
        H.ColorMap == "turbo" && isscalar(H.ColorBar) && isgraphics(H.ColorBar) ...
        && numel(H.ColorBar.Ticks) == 12 && string(H.ColorBar.TickLabels(1)) == "R01" ...
        && isequal(H.Legend.String, {'Session threshold (n=12)'}));
    S12.Group_Day = compose("2026-09-%02d", (1:height(S12))');
    S12.Group_Long = compose("Treatment phase %02d", (1:height(S12))');
    H = behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Day"), ...
        ColorMap = "parula");
    dayTick = string(H.ColorBar.TickLabels(1));
    dayTitle = string(H.ColorBar.Label.String);
    H = behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Long"), ...
        ColorMap = "parula");
    results(end+1,:) = check(nm + ": colour-bar ticks stay short: a shared prefix moves to the title, long ones are cut", ...
        dayTick == "01" && contains(dayTitle, "2026-09-") ...
        && all(strlength(string(H.ColorBar.TickLabels)) <= behavior.Plot.MAX_TICK_CHARS));
    fSubj = behavior.Facet("subject");
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorBy = fSubj, ColorMap = "copper");
    results(end+1,:) = check(nm + ": a gradient may be asked for on any facet; auto keeps subject categorical", ...
        H.ColorMap == "copper" && behavior.Plot.resolveColorMap("auto", fSubj) == "categorical");
    behavior.Plot.staircaseOverlay(ax, Rs, S12, ColorBy = behavior.Facet("manual", Name = "Run"), ColorMap = "turbo");
    hadBar = ~isempty(findall(ancestor(ax, 'figure'), 'Tag', 'BehaviorPlot:ColorBar'));
    H = behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorBy = fSubj);
    results(end+1,:) = check(nm + ": the next figure clears a colour bar the last one left", ...
        hadBar && isempty(H.ColorBar) && isempty(findall(ancestor(ax, 'figure'), 'Tag', 'BehaviorPlot:ColorBar')));
    bad = false;
    try
        behavior.Plot.staircaseOverlay(ax, Rs, cat.Sessions, ColorMap = "rainbow");
    catch
        bad = true;
    end
    results(end+1,:) = check(nm + ": an unknown colour map is refused", bad);
    H = behavior.Plot.staircaseOverlay(ax, {}, cat.Sessions);
    results(end+1,:) = check(nm + ": overlay of no results draws No data", localIsNoData(ax, H));
    H = behavior.Plot.staircaseOverlay(ax, struct([]), []);
    results(end+1,:) = check(nm + ": overlay of an empty struct draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 6: " + ME.message, false);
end

% One subject's six sessions, and the same with its first session's
% staircase taken away (a session with no tracked parameter).
Rs1 = Rs([Rs.Subject] == "S1");
Rgap = Rs1;
Rgap(1).Track = struct('TrialIndex', zeros(1, 0), 'Value', zeros(1, 0), 'Reversal', false(1, 0));
Rgap(1).Threshold = NaN;
noTrack = Rs;
for k = 1:numel(noTrack)
    noTrack(k).Track = Rgap(1).Track;
end
% A session's row (and band) is its ordinal within the subject.
T1 = behavior.Aggregate.thresholds(Rs1, cat.Sessions);
rowOf = @(r) double(T1.SessionOrdinal(T1.Key == r.Key));
gapRow = rowOf(Rgap(1));

%% 6b. staircaseStack
try
    H = behavior.Plot.staircaseStack(ax, Rs1, cat.Sessions);
    span = diff(H.ValueRange);
    inBand = true;
    for h = H.Track
        c = h.UserData.Level;
        inBand = inBand && all(h.YData >= H.Offsets(c) - 1e-9 & h.YData <= H.Offsets(c) + span + 1e-9);
    end
    results(end+1,:) = check(nm + ": stack: a band per session, first on top, every track inside its own band", ...
        isequal(H.Levels, string(1:6)') && issorted(flip(H.Offsets)) && H.Offsets(1) > H.Offsets(end) ...
        && numel(H.Track) == 6 && inBand && numel(localTagged(ax, "Track")) == 6);
    lens = arrayfun(@(h) numel(h.XData), H.Track);
    want = arrayfun(@(h) numel(Rs1(arrayfun(@(r) r.Key == h.UserData.Key, Rs1)).Track.Value), H.Track);
    results(end+1,:) = check(nm + ": stack: each track has its session's stimulus trials, drawn as steps", ...
        isequal(lens, want) && all(strcmp(get(H.Track, 'Type'), 'stair')));
    results(end+1,:) = check(nm + ": stack: bands labelled top to bottom, every other one shaded", ...
        isequal(string(ax.YTickLabel), string(6:-1:1)') && numel(H.Band) == 3 ...
        && all(arrayfun(@(p) isequal(p.FaceColor, behavior.Plot.BAND_SHADE), H.Band)));
    ref = median([Rs1(isfinite([Rs1.Threshold])).Threshold]);
    results(end+1,:) = check(nm + ": stack: the median threshold as a dotted reference in every band, a scale bar in dB", ...
        isscalar(H.Reference) && numel(H.Reference.YData) == 18 && strcmp(H.Reference.LineStyle, ':') ...
        && contains(H.Reference.DisplayName, sprintf('%.4g dB', ref)) ...
        && numel(H.ScaleBar) == 2 && endsWith(string(H.ScaleBar(2).String), " dB") ...
        && numel(localTagged(ax, "ScaleBar")) == 2 && any(contains(H.Legend.String, "Median threshold")));
    results(end+1,:) = check(nm + ": stack: no x tick under the scale bar", ...
        max(ax.XTick) <= max(arrayfun(@(h) max(h.XData), H.Track)) && ax.XLim(2) > max(ax.XTick));
    results(end+1,:) = check(nm + ": stack: thresholds at the tracks' ends, reversals only when asked", ...
        numel(H.Threshold) == sum(isfinite([Rs1.Threshold])) && isempty(H.Reversal));

    H = behavior.Plot.staircaseStack(ax, Rgap, cat.Sessions, ShowReversals = true);
    results(end+1,:) = check(nm + ": stack: a session with no staircase keeps its band, says so, gets no reference", ...
        numel(H.Track) == 5 && isscalar(H.Missing) && string(H.Missing.String) == "No staircase" ...
        && abs(H.Missing.Position(2) - (H.Offsets(gapRow) + diff(H.ValueRange) / 2)) < 1e-9 ...
        && numel(H.Reference.YData) == 15 && ~isempty(H.Reversal));

    H = behavior.Plot.staircaseStack(ax, Rs, cat.Sessions, Rows = fTag, Normalize = "fraction", Steps = false);
    results(end+1,:) = check(nm + ": stack by tag: two bands in phase order, n per band, every track ends at 1", ...
        isequal(H.Levels, ["Pre"; "Post"]) && isequal(string(ax.YTickLabel), ["Post (n=6)"; "Pre (n=6)"]) ...
        && numel(H.Track) == 12 && size(unique(vertcat(H.Track.Color), 'rows'), 1) == 2 ...
        && all(arrayfun(@(h) h.XData(end) == 1, H.Track)) && all(strcmp(get(H.Track, 'Type'), 'line')));
    H = behavior.Plot.staircaseStack(ax, Rs1, [], Reference = "none", ShowThresholds = false);
    H2 = behavior.Plot.staircaseStack(ax, Rs1, [], Reference = 1e6);
    results(end+1,:) = check(nm + ": stack: no reference when told none, or when it lies outside the tracks", ...
        isempty(H.Reference) && isempty(H.Threshold) && isempty(H2.Reference));
    H = behavior.Plot.staircaseStack(ax, Rs1, [], Reference = 30);
    results(end+1,:) = check(nm + ": stack: a stated reference is drawn at that value in each band", ...
        isscalar(H.Reference) && abs(H.Reference.YData(1) - (H.Offsets(1) + 30 - H.ValueRange(1))) < 1e-9 ...
        && startsWith(H.Reference.DisplayName, "Reference 30"));
    results(end+1,:) = check(nm + ": stack: a Reference that is no value is refused", ...
        throwsWith(@() behavior.Plot.staircaseStack(ax, Rs1, [], Reference = "banana"), 'behavior:Plot:InvalidReference'));
    H = behavior.Plot.staircaseStack(ax, {}, cat.Sessions);
    results(end+1,:) = check(nm + ": stack of no results draws No data", localIsNoData(ax, H));
    H = behavior.Plot.staircaseStack(ax, noTrack, cat.Sessions);
    results(end+1,:) = check(nm + ": stack with no staircase anywhere draws No data and says why", ...
        localIsNoData(ax, H) && contains(strjoin(string(H.NoData.String)), "staircase"));
catch ME
    results(end+1,:) = check(nm + ": group 6b: " + ME.message, false);
end

%% 6c. staircaseHeatmap
try
    H = behavior.Plot.staircaseHeatmap(ax, Rs1, cat.Sessions);
    G = H.Grid;
    fin = isfinite(G);
    lastTrial = max(arrayfun(@(r) max(r.Track.TrialIndex), Rs1));
    results(end+1,:) = check(nm + ": heatmap: a row per session, first on top, a column per trial", ...
        isequal(H.Levels, string(1:6)') && isequal(H.Count, ones(6, 1)) && isequal(size(G), [6 lastTrial]) ...
        && strcmp(ax.YDir, 'reverse') && isequal(string(ax.YTickLabel), string(1:6)'));
    results(end+1,:) = check(nm + ": heatmap: the image is the grid, transparent exactly where there is no data", ...
        isscalar(H.Heatmap) && isequaln(H.Heatmap.CData, G) && isequal(H.Heatmap.AlphaData, double(fin)) ...
        && isequal(ax.Color, behavior.Plot.MISSING_COLOR) && isscalar(localTagged(ax, "Heatmap")));
    held = true;
    for c = 1:6
        tr = Rs1(c).Track;
        cc = rowOf(Rs1(c));
        held = held && isequal(G(cc, tr.TrialIndex), tr.Value) ...
            && all(fin(cc, tr.TrialIndex(1):tr.TrialIndex(end))) && ~any(fin(cc, 1:tr.TrialIndex(1) - 1)) ...
            && ~any(fin(cc, tr.TrialIndex(end) + 1:end));
        between = setdiff(tr.TrialIndex(1):tr.TrialIndex(end), tr.TrialIndex);
        for j = between
            prev = find(tr.TrialIndex < j, 1, 'last');
            held = held && G(cc, j) == tr.Value(prev);
        end
    end
    results(end+1,:) = check(nm + ": heatmap: a cell holds the level of the last stimulus trial before it, missing outside the track", held);
    results(end+1,:) = check(nm + ": heatmap: a colour bar names the parameter; parula by default", ...
        isscalar(H.ColorBar) && contains(string(H.ColorBar.Label.String), "Depth (dB)") && H.ColorMap == "parula" ...
        && isequal(ax.Colormap, behavior.Plot.sequential("parula", 256)) ...
        && isequal(ax.CLim, [min(G(fin)) max(G(fin))]));

    H = behavior.Plot.staircaseHeatmap(ax, Rgap, cat.Sessions, Normalize = "trial", ShowReversals = true);
    G = H.Grid;
    fin = isfinite(G);
    seg = localSegments(H.Missing);
    inside = all(arrayfun(@(k) ~fin(round(seg(k, 2)), round(seg(k, 1))), 1:size(seg, 1)));
    results(end+1,:) = check(nm + ": heatmap by stimulus trial: a row holds its track from column 1, NaN past its end", ...
        all(arrayfun(@(k) isequal(G(rowOf(Rgap(k)), 1:numel(Rgap(k).Track.Value)), Rgap(k).Track.Value), 2:6)) ...
        && all(arrayfun(@(k) sum(fin(rowOf(Rgap(k)), :)) == numel(Rgap(k).Track.Value), 1:6)));
    results(end+1,:) = check(nm + ": heatmap: missing cells hatched -- every stroke inside a missing cell -- and named in the key", ...
        isscalar(H.Missing) && ~isempty(seg) && inside && isequal(H.Missing.Color, behavior.Plot.HATCH_COLOR) ...
        && any(startsWith(string(H.Legend.String), "No data, hatched")) && strcmp(H.Legend.Location, 'southoutside'));
    results(end+1,:) = check(nm + ": heatmap: a session with no staircase is a hatched row that says so", ...
        ~any(fin(gapRow, :)) && string(ax.YTickLabel{gapRow}) == gapRow + " (no staircase)");
    results(end+1,:) = check(nm + ": heatmap: reversals marked in one-session rows", ...
        isscalar(H.Reversal) && numel(H.Reversal.XData) == sum(arrayfun(@(r) sum(r.Track.Reversal), Rgap)));

    H = behavior.Plot.staircaseHeatmap(ax, Rs1, [], Normalize = "fraction", NumBins = 40, ColorMap = "turbo");
    results(end+1,:) = check(nm + ": heatmap by fraction: NumBins columns, every cell filled, no hatch or key", ...
        isequal(size(H.Grid), [6 40]) && all(isfinite(H.Grid(:))) && isempty(H.Missing) && isempty(H.Legend) ...
        && abs(H.X(1) - 1/80) < 1e-12 && isequal(ax.XLim, [0 1]) && H.ColorMap == "turbo");
    v = Rs1(1).Track.Value;
    r1 = rowOf(Rs1(1));
    results(end+1,:) = check(nm + ": heatmap by fraction: a slice takes the trial its centre falls in", ...
        isequal(H.Grid(r1, [1 40]), v([1 end])) && H.Grid(r1, 20) == v(ceil(19.5 / 40 * numel(v))));

    Hm = behavior.Plot.staircaseHeatmap(ax, Rs, cat.Sessions, Rows = fTag, Normalize = "trial", ShowReversals = true);
    Hd = behavior.Plot.staircaseHeatmap(ax, Rs, cat.Sessions, Rows = fTag, Normalize = "trial", Combine = "median");
    pre = Rs(arrayfun(@(r) any(r.Tags == "Pre"), Rs));
    n = max(arrayfun(@(r) numel(r.Track.Value), Rs));
    M = nan(numel(pre), n);
    for k = 1:numel(pre)
        M(k, 1:numel(pre(k).Track.Value)) = pre(k).Track.Value;
    end
    results(end+1,:) = check(nm + ": heatmap by tag: a row per phase combining its sessions, mean or median", ...
        isequal(Hm.Levels, ["Pre"; "Post"]) && isequal(Hm.Count, [6; 6]) ...
        && isequaln(Hm.Grid(1, :), mean(M, 1, 'omitnan')) && isequaln(Hd.Grid(1, :), median(M, 1, 'omitnan')) ...
        && isequal(string(ax.YTickLabel), ["Pre (n=6)"; "Post (n=6)"]));
    results(end+1,:) = check(nm + ": heatmap: no reversals in a combined row", isempty(Hm.Reversal));

    H = behavior.Plot.staircaseHeatmap(ax, Rs1, [], ColorMap = "categorical", CLim = [10 50]);
    results(end+1,:) = check(nm + ": heatmap: Distinct colours draws as Auto; a stated CLim is kept", ...
        H.ColorMap == "parula" && isequal(ax.CLim, [10 50]));
    results(end+1,:) = check(nm + ": heatmap: a CLim that is no range is refused", ...
        throwsWith(@() behavior.Plot.staircaseHeatmap(ax, Rs1, [], CLim = [5 5]), 'behavior:Plot:InvalidCLim'));
    H = behavior.Plot.staircaseHeatmap(ax, {}, []);
    results(end+1,:) = check(nm + ": heatmap of no results draws No data", localIsNoData(ax, H));
    H = behavior.Plot.staircaseHeatmap(ax, noTrack, cat.Sessions);
    results(end+1,:) = check(nm + ": heatmap with no staircase anywhere draws No data", ...
        localIsNoData(ax, H) && isempty(findall(ancestor(ax, 'figure'), 'Tag', 'BehaviorPlot:ColorBar')));
catch ME
    results(end+1,:) = check(nm + ": group 6c: " + ME.message, false);
end

%% 7. psychometric
try
    good = find(arrayfun(@(r) r.Fit.Converged && r.Fit.Identifiable, Rs), 1);
    results(end+1,:) = check(nm + ": the fixture has a converged fit", ~isempty(good));
    F = Rs(good).Fit;
    H = behavior.Plot.psychometric(ax, F, Unit = "dB");
    cu = localTagged(ax, "Curve");
    results(end+1,:) = check(nm + ": psychometric: proportions, a curve of >10 points, a threshold line", ...
        isscalar(localTagged(ax, "Proportion")) && isscalar(cu) && numel(cu.XData) > 10 ...
        && isscalar(localTagged(ax, "Threshold")) && isequal(H.Threshold.XData, [F.Threshold F.Threshold]));
    results(end+1,:) = check(nm + ": marker area follows NumTotal", ...
        numel(unique(H.Proportion.SizeData)) > 1 || isscalar(unique(F.NumTotal)));
    results(end+1,:) = check(nm + ": psychometric labels: level with unit, proportion", ...
        contains(ax.XLabel.String, "(dB)") && contains(ax.YLabel.String, "Proportion"));
    Fc = F;
    Fc.CI.ThresholdLo = F.Threshold - 1;
    Fc.CI.ThresholdHi = F.Threshold + 1;
    Fc.CI.Level = 0.95;
    behavior.Plot.psychometric(ax, Fc);
    ci = localTagged(ax, "CI");
    results(end+1,:) = check(nm + ": a finite CI is a shaded band", isscalar(ci) && isequal(sort(unique(ci.XData))', Fc.Threshold + [-1 1]));
    behavior.Plot.psychometric(ax, Fc, ShowCI = false, ShowCounts = false);
    results(end+1,:) = check(nm + ": ShowCI false: no band", isempty(localTagged(ax, "CI")));

    Fn = F;
    Fn.Converged = false;
    Fn.Message = "Complete separation: the slope is unbounded.";
    H = behavior.Plot.psychometric(ax, Fn);
    results(end+1,:) = check(nm + ": a non-converged fit draws its proportions and its message, no curve", ...
        isscalar(localTagged(ax, "Proportion")) && isempty(localTagged(ax, "Curve")) ...
        && isscalar(H.Message) && contains(H.Message.String, "Complete separation"));
    Fe = behavior.fit.Builtin.empty();
    Fe.Message = "Fewer than two distinct levels.";
    H = behavior.Plot.psychometric(ax, Fe);
    results(end+1,:) = check(nm + ": an empty fit with a message draws No data and the message", ...
        localIsNoData(ax, H) && any(contains(string(H.NoData.String), "Fewer than two distinct levels")));
    H = behavior.Plot.psychometric(ax, []);
    results(end+1,:) = check(nm + ": psychometric of [] draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 7: " + ME.message, false);
end

%% 8. reversalHistogram
try
    H = behavior.Plot.reversalHistogram(ax, Rs(1));
    results(end+1,:) = check(nm + ": histogram of the reversal values with mean and median lines", ...
        isscalar(localTagged(ax, "Histogram")) && sum(H.Histogram.Values) == numel(Rs(1).ReversalValues) ...
        && abs(H.Mean.Value - mean(Rs(1).ReversalValues)) < 1e-12 ...
        && abs(H.Median.Value - median(Rs(1).ReversalValues)) < 1e-12);
    results(end+1,:) = check(nm + ": histogram labels: parameter at reversal with unit, count", ...
        contains(ax.XLabel.String, "Depth at reversal (dB)") && ax.YLabel.String == "Count");
    H = behavior.Plot.reversalHistogram(ax, Rs, Unit = "dB SPL");
    results(end+1,:) = check(nm + ": several results are pooled; a stated unit wins", ...
        sum(H.Histogram.Values) == numel([Rs.ReversalValues]) && contains(ax.XLabel.String, "dB SPL"));
    R0 = Rs(1);
    R0.ReversalValues = zeros(1, 0);
    H = behavior.Plot.reversalHistogram(ax, R0);
    results(end+1,:) = check(nm + ": no reversals draws No data", localIsNoData(ax, H));
    H = behavior.Plot.reversalHistogram(ax, struct([]));
    results(end+1,:) = check(nm + ": histogram of no results draws No data", localIsNoData(ax, H));
catch ME
    results(end+1,:) = check(nm + ": group 8: " + ME.message, false);
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

function h = localTagged(ax, role)
h = findall(ax, 'Tag', char("BehaviorPlot:" + role));
end

function n = localCount(h)
% Finite markers across line objects.
n = sum(arrayfun(@(x) sum(isfinite(double(x.YData))), h));
end

function y = localYData(h)
y = cell2mat(arrayfun(@(x) reshape(double(x.YData), 1, []), reshape(h, 1, []), 'UniformOutput', false));
end

function x = localXData(h)
x = cell2mat(arrayfun(@(v) reshape(double(v.XData), 1, []), reshape(h, 1, []), 'UniformOutput', false));
end

function c = localColorOf(h, level)
c = [];
for k = 1:numel(h)
    if startsWith(string(h(k).DisplayName), level + " ")
        c = h(k).MarkerFaceColor;
    end
end
end

function mid = localSegments(h)
% The midpoint [x y] of each stroke of a NaN-separated line, one row each.
mid = zeros(0, 2);
if isempty(h), return, end
x = h.XData;
y = h.YData;
k = find(~isnan(x(1:end-1)) & ~isnan(x(2:end)));
mid = [reshape(x(k) + x(k + 1), [], 1), reshape(y(k) + y(k + 1), [], 1)] / 2;
end

function tags = localTagSet(ax)
tags = unique(string(get(findall(ax.Children, 'flat'), 'Tag')));
end

function tf = localIsNoData(ax, H)
t = localTagged(ax, "NoData");
tf = false;
if ~isscalar(t), return, end
s = string(t.String);
tf = isequal(t, H.NoData) && startsWith(s(1), "No data") ...
    && isscalar(ax.Children);
end

function rgb = localHex(hex)
hex = char(erase(reshape(string(hex), [], 1), "#"));
rgb = [hex2dec(hex(:, 1:2)) hex2dec(hex(:, 3:4)) hex2dec(hex(:, 5:6))] / 255;
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

function localCleanup(root, cache, figs)
for f = figs
    if isgraphics(f), delete(f); end
end
for d = {root, cache}
    try
        if isfolder(d{1}), rmdir(d{1}, 's'); end
    catch
    end
end
end
